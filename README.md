# Can a crypto vault change its rules after you deposit? A read-only check of the first Rayls vault's launch-deposit contract

**Short answer:** yes, when one key can upgrade the code. On 19 Oct 2026 the launch-deposit contract of the first Rayls vault was upgraded in a single block by one account that holds every admin role, and the new code changed the reward rate of a week that was still open. The verified original code blocked that. Every deposit had arrived three days earlier and no depositor's credited reward was cut. Everything below can be re-checked with the scripts in this repo, which only read public data.

All times are UTC. Contract state read on 23 Oct 2026 14:03 from `https://mainnet-rpc.rayls.com` and cross-checked on `explorer.rayls.com`; the contract's full event history (`contract-events.txt`) read from the explorer API on 24 Oct 2026.

## Contracts and transactions

| What | Address or hash |
|---|---|
| Launch-deposit contract (ERC1967 proxy) | `0x5B9565e27F5d50B14D3f660799f87e829A53fab2` |
| Original code, VaultSeed 1.0.0 (source verified) | `0x39FfAe6736A9477797548a17019d544c3dbE9f67` |
| New code, 1.1.0 (source not verified) | `0x39Bf309Dba73c90F93f9aF74eEdB673f53447aCB` |
| Account that deployed and upgraded it | `0x633Ac5e2315b973417e8caa6B3Ad2162e0461ce1` |
| Deposit token BRL1.p | `0xA069d3798FEAb32994aC5D98A9F011DA6024f334` |
| New code created, block 12820048, 15:48:50 | `0xa8c2b0518f3e9ed5a426f1fe3051ddd7b425d8fa306ca7b9e9a2a130564c3279` |
| upgradeToAndCall, same block 12820048 | `0x744f833b2e1e59430337c5c87ad1644db0f58d6a137eef9d9363f3bcef0e1377` |
| 0xf2eab735(5000), block 12820095, 15:49:53 | `0x5199af7a8e3c91ef9383944dbb272cbe7c796acfae0efb2553524472b61a73f6` |

## What is documented

- The original code (VaultSeed, `VERSION = "1.0.0"`) is verified on the Rayls explorer. It fixes each deposit's RLS at deposit time (amount x week rate / 1000). Its header comment says: "Rates of weeks that have opened are frozen, so per-week RLS stays derivable." `setWeek` reverts with `WeekAlreadyOpened` once a week's start time has passed. Upgrades are gated by `_authorizeUpgrade` with `onlyRole(UPGRADER_ROLE)`.
- The same code expected upgrades: it says RLS is paid through validator staking "by a user-initiated call added in a later upgrade".
- The Rayls launch blog (15 Oct) lists 10,000 / 8,000 / 6,000 / 4,000 RLS per 1,000 BRL1.p for weeks 1 to 4, a lock until 19 Nov 2026, and says "The vault's terms are not final."
- Lagoon, the vault technology partner named at the Rayls AMA, documents that a vault can only be upgraded to Lagoon-whitelisted implementations and that every upgrade waits for a delay the admin sets between 24 hours and 30 days, which "gives investors time to evaluate the incoming change and exit the vault if needed."

## What I verified myself

From `vault-report-v3-20261023-1402-UTC.txt` (output of `vault-check.ps1`), `code-dump-log.txt`, the two comparison scripts and the explorer:

1. **Deposits.** Nine BRL1.p deposits from six wallets, all between 15 Oct 11:07:51 and 16 Oct 15:39:20, sum 250,000. Each `Deposited` event is week 1 with `rlsEarned` = amount x 10. No deposit after that (checked 24 Oct), even though the cap went to 1,000,000 on 19 Oct.

   | Time (UTC) | Wallet | BRL1.p |
   |---|---|---|
   | 15 Oct 11:07:51 | 0x4d76...7e22 | 1 |
   | 15 Oct 11:56:34 | 0xc7e3...f554 | 10 |
   | 15 Oct 15:51:38 | 0x9390...8454 | 50.161295 |
   | 15 Oct 16:10:09 | 0x9390...8454 | 4,670.039696 |
   | 15 Oct 16:38:00 | 0x3d6c...b2b3 | 94,828.782983 |
   | 15 Oct 20:37:13 | 0xc7e3...f554 | 365.895698 |
   | 16 Oct 15:06:15 | 0x9f93...0603 | 100,000 |
   | 16 Oct 15:18:02 | 0x4dee...8fdc | 46,994.594239 |
   | 16 Oct 15:39:20 | 0x4dee...8fdc | 3,079.526089 |

2. **Cap history.** The initializer set a total cap of 500,000 at deployment (14 Oct). Then `setLimits`: 100,000 BRL1.p on 15 Oct 14:51:57, 250,000 on 16 Oct 15:00:02, 1,000,000 on 19 Oct 15:50:40. The deposit that filled the 250,000 cap landed at 15:39:20, 39 min 18 s after the raise.
3. **The upgrade.** In block 12820048 (19 Oct 15:48:50) `0x633a...1ce1` deployed new code and called `upgradeToAndCall` to it. Same block, so no onchain waiting period. The upgrade emitted only `Upgraded`, no `Initialized`, so no re-initializer ran. The new code returns `VERSION()` = 1.1.0 (also read directly from both implementations: old 1.0.0, new 1.1.0). As of 23 Oct its source is not published on the explorer.
4. **The rate change.** At deployment the contract logged `WeekSet` for weeks 1 to 4 at 10,000 / 8,000 / 6,000 / 4,000. On 19 Oct, 63 seconds after the upgrade (block 12820095), the same account called `0xf2eab735` with 5000. The transaction log shows `WeekSet(week 1, rlsPerThousand 5000)`. Week 1 was still open (deposits until 22 Oct 23:59:59). `0xf2eab735` is the first 4 bytes of `keccak256("setOpenWeekRate(uint128)")`, matched by hashing the candidate name. Weeks 2 to 4 were then set to 4,000 / 3,000 / 2,000 with `setWeek`, and the total cap to 1,000,000.
5. **Which functions exist.** `compare_selectors.py` lists the dispatcher selectors of both bytecodes: old 14,217 bytes with 56 selectors, new 14,657 bytes with the same 56 plus `0xf2eab735` (setOpenWeekRate) and `0xb5190e4a` (a getter that reads one new stored value; name not recovered). The planned staking-payout call is not among them.
6. **What changed inside the code.** `opcode_diff.py` compares the two opcode streams, masking only values that point at jump destinations (they move whenever code is added). Similarity is 97.2 percent across 60 differing regions: 13 are the dispatcher re-ordered around the two new selectors, 34 are data offsets shifted by the same 408 bytes, 5 are new or moved code blocks, 3 load the same WeekSet event ID from code instead of inline, 1 is the compiler metadata, and 4 are changed constants: the version string (1.0.0 to 1.1.0) and, three times, the code's own address used by the UUPS upgrade check. I found no other change to the old functions. This is a bytecode reading, not the source.
7. **Who can change it.** `0x633a...1ce1` holds DEFAULT_ADMIN_ROLE, UPGRADER_ROLE, OPERATOR_ROLE and PAUSER_ROLE, and has 0 bytes of code, so onchain it is one signing key, not a multisig contract. The `RoleGranted` events show no other account was ever given those roles; `0x7513...1431` holds only WHITELIST_MANAGER. There are no `RoleRevoked` events.
8. **What depositors got.** All six depositing wallets were credited 10,000 RLS per 1,000 BRL1.p (2,500,000 RLS in total). Week 1 now reads 5,000, which would give 1,250,000 for the same deposits. This matches what AJ said at the Rayls AMA on 20 Oct (8:18): the initial R$250K got 10,000 per 1,000.
9. **Where the money sits.** The contract holds 250,000 BRL1.p, `vault()` was still the zero address on 23 Oct, and the lock ends 2026-11-19 23:59:59.

## My analysis

- The upgrade was the route to change week 1's rate: the verified code refused it, and the new function was called 63 s after the switch. Because RLS is fixed at deposit time and every deposit came before the change, credited rewards were not touched. The per-week rate table no longer explains what week 1 was credited, which is the property the original comment promised.
- Upgrades were planned for the staking payout. This one added a way to change an opened week's rate instead.
- The AMA answer (vault technology from Lagoon, audited) is about the vault. Lagoon's upgrade delay protects the vault, not this deposit contract, which is not connected to any vault yet and changed in one block.
- While deposits are locked, a delay cannot offer an exit. What it offers is time for anyone to read new code before it runs. AJ expects an initial lock of about 3 months in the vault itself (AMA 22:08), so the same trade-off applies there. L2BEAT uses the same idea for rollups: Stage 1 needs at least 7 days for users to exit before an upgrade that does not come from a Security Council.

## Still unconfirmed

- Behaviour of 1.1.0 at source level. The opcode diff finds no logic change in the old functions, but only the published source proves it.
- How the single key is protected off-chain. MPC or a hardware wallet would still look like one key onchain.
- All reads went through one public RPC node and the Rayls explorer.

## Reproduce it

Windows: double-click `vault-check.bat` (writes `vault-report-v3-<time>-UTC.txt`) and `code-dump.bat` (writes `code-old.hex`, `code-new.hex`, `code-dump-log.txt`). Set `VAULT_PAUSE=0` to skip the pauses between screens, or `VAULT_RPC` to use another node. Then:

```
python compare_selectors.py code-old.hex code-new.hex
python opcode_diff.py code-old.hex code-new.hex
```

The saved outputs are `compare-selectors-output.txt` and `opcode-diff-output.txt`. `contract-events.txt` lists every event the contract emitted, from the explorer API. The scripts only send read requests (`eth_call`, `eth_getCode`, `eth_getStorageAt`, `eth_getTransactionByHash`, `eth_getBlockByNumber`). They never sign or send a transaction.

## Sources

- Launch-deposit contract and its deposits: https://explorer.rayls.com/address/0x5B9565e27F5d50B14D3f660799f87e829A53fab2?tab=token_transfers
- Rayls launch blog: https://www.rayls.com/blog/first-vault-on-rayls-launch-deposits-open
- Rayls AMA, 20 Oct 2026: https://www.youtube.com/live/cRsydQpZYos (8:18 rewards, 22:08 lock, 34:56 my question, 35:04 to 35:50 answer)
- Lagoon docs: https://docs.lagoon.finance/vault/upgradability-and-opt-in-proxy
- L2BEAT Stages: https://l2beat.com/stages
- EIP-1967: https://eips.ethereum.org/EIPS/eip-1967
