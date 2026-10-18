# Findings: Automated Jury Pool Dispatcher & Courtroom Bucket Routing

## Architecture & Existing System Insights
1. **nyx_judiciary Topology**:
   - `config.lua` contains `Config.Jury` (DefaultRequiredCount=5, MinimumQuorum=3, DeliberationTimeout=900, ExemptJobs, DeliberationBucketOffset=2000).
   - `config.lua` contains `Config.Courtroom` (InteriorCenter, JudgeBench, WitnessStand, ProsecutionBench, DefenseBench, JuryBox[6], PublicGallery, DeliberationChamber).
   - `nyx_judiciary/server/jury.lua` contains baseline `SummonJury`, `SeatJuror`, `ExcuseJuror`, `CastSecretBallot`, `GetJuryStatus`.
   - `nyx_judiciary/client/courtroom.lua` defines `CourtSeats` with 6 jury seats, handles sitting kinematics and text display.
   - `nyx_judiciary/fxmanifest.lua` only has `config.lua` in `shared_scripts`. It needs `'shared/jury.lua'`.
2. **Virtual Routing Bucket Architecture**:
   - `nyx_core/server/buckets.lua` and `exports.lua`:
     - `exports['nyx_core']:SetRoutingBucket(src, bucketId)`
     - `exports['nyx_core']:GetRoutingBucket(src)`
     - `exports['nyx_core']:SetDefaultBucket(src)`
     - `Player(source).state.routingBucket` is synchronized on bucket transitions.
   - Trials should have an isolated `routing_bucket` (e.g. 2100..2999) to prevent overworld interference and desync.
   - Deliberation chamber should have a further isolated `deliberation_bucket` (e.g. courtroomBucket + 2000 = 4100..4999) so nobody can hear or influence jury votes.
3. **Treasury Integration**:
   - When a trial concludes, seated jurors who fulfilled civic duty receive a stipend (e.g. $500) transferred from `gov:city:master` to `citizen:<citId>` via `exports['nyx_treasury']:ExecuteTransfer`.
4. **Fisher-Yates Shuffle Math**:
   - For $i = N \dots 2$, pick uniform random $j \in [1, i]$, swap elements $i$ and $j$.
   - Must be $O(N)$, preserve all elements, and guarantee uniform distribution across all $N!$ permutations.
