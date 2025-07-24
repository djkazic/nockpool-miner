use crate::config::Config;

use quiver::types::{Template, Submission, Target};
use assets::MINER;

use sysinfo::System;
use tokio::sync::{Mutex, watch};
use anyhow::Result;
use tracing::info;
use rand::Rng;
use bytes::Bytes;

use nockapp::save::SaveableCheckpoint;
use nockapp::utils::NOCK_STACK_SIZE_TINY;
use nockapp::kernel::form::SerfThread;
use nockapp::noun::slab::NounSlab;
use nockapp::noun::AtomExt;
use nockapp::NounExt;
use nockapp::wire::{WireRepr, WireTag};

use nockvm::noun::{Atom, D, T};
use nockvm::interpreter::NockCancelToken;

use zkvm_jetpack::form::PRIME;

use nockvm_macros::tas;

pub async fn start(
    config: Config,
    mut template_rx: watch::Receiver<Template>,
    submission_tx: watch::Sender<Submission>,
) -> Result<()> {
    let num_threads = {
        let sys = System::new_all();
        let logical_cores = sys.cpus().len() as u32;
        let calculated_threads = (logical_cores * 2).saturating_sub(4).max(1);
        if let Some(max_threads) = config.max_threads {
            max_threads.min(calculated_threads) as u64
        } else {
            calculated_threads as u64
        }
    };
    info!("mining with {} threads", num_threads);

    let mut mining_attempts = tokio::task::JoinSet::<(
        SerfThread<SaveableCheckpoint>,
        u64,
        Result<NounSlab, anyhow::Error>,
    )>::new();

    let network_only = config.network_only;

    if network_only {
        info!("mining for network target only");
    } else {
        info!("mining for pool and network targets");
    }

    let hot_state = zkvm_jetpack::hot::produce_prover_hot_state();
    let test_jets_str = std::env::var("NOCK_TEST_JETS").unwrap_or_default();
    let test_jets = nockapp::kernel::boot::parse_test_jets(test_jets_str.as_str());

    let mining_data: Mutex<Option<Template>> = Mutex::new(None);
    let mut cancel_tokens: Vec<NockCancelToken> = Vec::<NockCancelToken>::new();

    loop {
        tokio::select! {
            mining_result = mining_attempts.join_next(), if !mining_attempts.is_empty() => {
                let mining_result = mining_result.expect("Mining attempt failed");
                let (serf, id, slab_res) = mining_result.expect("Mining attempt result failed");
                let slab = slab_res.expect("Mining attempt result failed");

                let result = unsafe { slab.root() };
                let result_cell = result.as_cell().expect("Expected result to be a cell");

                let hed = result_cell.head();

                if hed.is_atom() && hed.eq_bytes("poke") {
                    //  mining attempt was cancelled. restart with current block header.
                    info!("using new template on thread={id}");
                    mine(serf, mining_data.lock().await, &mut mining_attempts, None, id).await;
                    continue;
                } 

                let effect = hed.as_cell().expect("Expected result to be a cell");

                if effect.head().eq_bytes("miss") {
                    info!("solution did not hit targets on thread={id}, trying again");
                    let mut nonce_slab = NounSlab::new();
                    nonce_slab.copy_into(effect.tail());
                    mine(serf, mining_data.lock().await, &mut mining_attempts, Some(nonce_slab), id).await;
                    continue;
                }

                let target_type = if effect.head().eq_bytes("pool") {
                    Target::Pool
                } else if effect.head().eq_bytes("network") {
                    Target::Network
                } else {
                    info!("solution found but invalid target: {:?}", effect.head());
                    mine(serf, mining_data.lock().await, &mut mining_attempts, None, id).await;
                    continue;
                };

                if network_only && target_type != Target::Network {
                    info!("solution did not hit network target on thread={id}, trying again");
                    mine(serf, mining_data.lock().await, &mut mining_attempts, None, id).await;
                    continue;
                }

                let success_message = effect.tail().as_cell().expect("Expected result to be a cell");

                // 2
                let mut commit_slab: NounSlab = NounSlab::new();
                commit_slab.copy_into(success_message.head());
                let commit = commit_slab.jam();

                // 3
                let success_message_tail = success_message.tail().as_cell().expect("Expected result to be a cell");

                // 6
                let digest = Bytes::from(success_message_tail.head().as_atom()?.to_le_bytes());

                // 7
                let mut proof_slab: NounSlab = NounSlab::new();
                proof_slab.copy_into(success_message_tail.tail());
                let proof = proof_slab.jam();

                let submission = Submission::new(target_type.clone(), commit, digest, proof);
                info!(
                    "solution found on thread={id} for target={:?}. Proof size: {:?} KB. Submitting to nockpool.",
                    target_type,
                    ((submission.proof.len() as f64) / 1024.0 * 100.0).round() / 100.0,
                );
                submission_tx.send(submission).expect("Failed to send submission");

                mine(serf, mining_data.lock().await, &mut mining_attempts, None, id).await;
            }
            _ = template_rx.changed() => {
                let template = template_rx.borrow_and_update().clone();

                *(mining_data.lock().await) = Some(template);

                if mining_attempts.is_empty() {
                    for i in 0..num_threads {
                        let kernel = Vec::from(MINER);
                        let serf = SerfThread::<SaveableCheckpoint>::new(
                            kernel,
                            None,
                            hot_state.clone(),
                            NOCK_STACK_SIZE_TINY,
                            test_jets.clone(),
                            false,
                        )
                        .await
                        .expect("Could not load mining kernel");

                        cancel_tokens.push(serf.cancel_token.clone());

                        mine(serf, mining_data.lock().await, &mut mining_attempts, None, i).await;
                    }
                    info!("Received nockpool template! Starting {} mining threads", num_threads);
                } else {
                    // Mining is already running so cancel all the running attemps
                    // which are mining on the old block.
                    info!("New nockpool template! Restarting {} mining threads", num_threads);
                    for token in &cancel_tokens {
                        token.cancel();
                    }
                }
            },
        }
    }
}
/*
        %template
        version=?(%0 %1 %2)
        commit=block-commitment:t
        nonce=noun-digest:tip5
        network-target=bignum:bignum
        pool-target=bignum:bignum
        pow-len=@        
*/
async fn mine(
    serf: SerfThread<SaveableCheckpoint>,
    template: tokio::sync::MutexGuard<'_, Option<Template>>,
    mining_attempts: &mut tokio::task::JoinSet<(
        SerfThread<SaveableCheckpoint>,
        u64,
        Result<NounSlab>,
    )>,
    nonce: Option<NounSlab>,
    id: u64,
) {
    let mut slab = NounSlab::new();
    // let's first deal with the nonce
    let nonce = if let Some(nonce) = nonce {
        nonce
    } else {
        let mut rng = rand::thread_rng();
        let mut nonce_slab: NounSlab = NounSlab::new();
        let mut nonce_cell = Atom::from_value(&mut nonce_slab, rng.gen::<u64>() % PRIME)
            .expect("Failed to create nonce atom")
            .as_noun();
        for _ in 1..5 {
            let nonce_atom = Atom::from_value(&mut nonce_slab, rng.gen::<u64>() % PRIME)
                .expect("Failed to create nonce atom")
                .as_noun();
            nonce_cell = T(&mut nonce_slab, &[nonce_atom, nonce_cell]);
        }
        nonce_slab.set_root(nonce_cell);
        nonce_slab
    };

    // now we deal with the rest of the template noun
    let template_ref = template.as_ref().expect("Mining data should already be initialized");

    let version_atom = Atom::from_bytes(&mut slab, (&template_ref.version.clone()).into());
    let commit = slab.cue_into(template_ref.commit.clone().into()).expect("Failed to cue commit");
    let nonce = slab.copy_into(unsafe { *(nonce.root()) });
    let network_target = slab.cue_into(template_ref.network_target.clone().into()).expect("Failed to cue network target");
    let pool_target = slab.cue_into(template_ref.pool_target.clone().into()).expect("Failed to cue pool target");
    let pow_len_atom = Atom::from_bytes(&mut slab, (&template_ref.pow_len.clone()).into());
    let noun = T(&mut slab, &[
        D(tas!(b"template")),
        version_atom.as_noun(),
        commit,
        nonce,
        network_target,
        pool_target,
        pow_len_atom.as_noun(),
    ]);

    slab.set_root(noun);

    let wire = WireRepr::new("miner", 1, vec![WireTag::String("candidate".to_string())]);
    mining_attempts.spawn(async move {
        info!("starting mining attempt on thread={id}");
        let result = serf.poke(wire.clone(), slab.clone()).await.map_err(|e| anyhow::anyhow!(e));
        (serf, id, result)
    });
}
