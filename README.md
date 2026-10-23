# Can a crypto vault change its rules after you deposit? A read-only check of the first Rayls vault's launch-deposit contract

**Short answer:** yes, when one key can upgrade the code. On 19 Oct 2026 the launch-deposit contract of the first Rayls vault was upgraded in a single block by one account that holds every admin role, and the new code changed the reward rate of a week that had already opened. The verified original code blocked that. No depositor's credited reward was cut. Everything below can be re-checked with the scripts in this repo, which only read public data.

All times are UTC. Data read on 23 Oct 2026 from `https://mainnet-rpc.rayls.com` and `explorer.rayls.com`.

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
| 0xf2eab735(5000), block 12820095, 15:49:53 | `0x5199af7a8e3c91ef9383944dbb272cbe7c796acfaeefb2553524472b61a73f6` |

## What is documented

- The original code (VaultSeed, `VERSION = "1.0.0"`) is verified on the Rayls explorer. Its header comment says: "Rates of weeks that have opened are frozen, so per-week RLS stays derivable." `setWeek` reverts with `WeekAlreadyOpened` once a week's start time has passed. Upgrades are gated by `_authorizeUpgrade` with `onlyRole(UPGRADER_ROLE)`.
- The Rayls launch blog (15 Oct) lists 10,000 / 8,000 / 6,000 / 4,000 RLS per 1,000 BRL1.p for weeks 1 to 4, a lock until 19 Nov 2026, and says "The vault's terms are not final."
- Lagoon, the vault technology partner named at the Rayls AMA, documents that a vault can only be upgraded to Lagoon-whitelisted implementations and that every upgrade waits for a delay the admin sets between 24 hours and 30 days, which "gives investors time to evaluate the incoming change and exit the vault if needed."

## What I verified myself

From `vault-report-v3-20261023-1402-UTC.txt` (output of `vault-check.ps1`) and the explorer:

1. **Cap history.** Total cap 100,000 BRL1.p on 15 Oct 14:51:57, 250,000 on 16 Oct 15:00:02, 1,000,000 on 19 Oct 15:50:40. The deposit that filled the 250,000 cap landed at 15:39:20, 39 min 18 s after the raise.
2. **The upgrade.** In block 12820048 (19 Oct 15:48:50) `0x633a...1ce1` deployed new code and called `upgradeToAndCall` to it. Same block, so no waiting period. The new code returns `VERSION()` = 1.1.0 (also read directly from both implementations in `code-dump-log.txt`: old 1.0.0, new 1.1.0). Its source is not published on the explorer.
3. **The rate change.** 63 seconds later (block 12820095) the same account called `0xf2eab735` with 5000. The transaction log shows `WeekSet(week 1, rlsPerThousand 5000)`. `0xf2eab735` is the first 4 bytes of `keccak256("setOpenWeekRate(uint128)")`, matched by hashing the candidate name. Weeks 2 to 4 were then set to 4,000 / 3,000 / 2,000 with `setWeek`, and the total cap to 1,000,000.
4. **What changed in the code.** `compare_selectors.py` lists the dispatcher selectors of both bytecodes: old 14,217 bytes with 56 selectors, new 14,657 bytes with the same 56 plus `0xf2eab735` (setOpenWeekRate) and `0xb5190e4a` (reads one new stored value; name not recovered).
5. **Who can change it.** `0x633a...1ce1` holds DEFAULT_ADMIN_ROLE, UPGRADER_ROLE, OPERATOR_ROLE and PAUSER_ROLE, and has 0 bytes of code, so onchain it is one signing key, not a multisig contract.
6. **What depositors got.** All six depositing wallets were credited 10,000 RLS per 1,000 BRL1.p (2,500,000 RLS in total). Week 1 now reads 5,000, which would give 1,250,000 for the same deposits. This matches what AJ said at the Rayls AMA on 20 Oct (8:18): the initial R$250K got 10,000 per 1,000.
7. **Where the money sits.** The contract holds 250,000 BRL1.p, `vault()` is still the zero address, and the lock ends 2026-11-19 23:59:59.

## My analysis

- The upgrade was the route to change week 1's rate: the verified code refused it, and the new function was called 63 s after the switch. Credited rewards were not touched, but the per-week rate table no longer explains what week 1 was credited, which is the property the original comment promised.
- The AMA answer (vault technology from Lagoon, audited) is about the vault. Lagoon's upgrade delay protects the vault, not this deposit contract, which is not connected to any vault yet and changed in one block.
- While deposits are locked, a delay cannot offer an exit. What it offers is time for anyone to read new code before it runs. AJ expects an initial lock of about 3 months in the vault itself (AMA 22:08), so the same trade-off applies there. L2BEAT uses the same idea for rollups: Stage 1 needs at least 7 days for users to exit before an upgrade that does not come from a Security Council.

## Still unconfirmed

- What the existing functions do in 1.1.0 (for example withdraw and token recovery) until its source is published.
- How the single key is protected off-chain. MPC or a hardware wallet would still look like one key onchain.
- The pre-upgrade state read from a node: the public RPC is pruned, so "before" comes from the transactions and the verified source.
- All reads went through one public RPC node and one explorer.

## Reproduce it

Windows: double-click `vault-check.bat` (writes `vault-report-v3-<time>-UTC.txt`) and `code-dump.bat` (writes `code-old.hex`, `code-new.hex`, `code-dump-log.txt`). Set `VAULT_PAUSE=0` to skip the pauses between screens, or `VAULT_RPC` to use another node. Then:

```
python compare_selectors.py code-old.hex code-new.hex
```

The scripts only send read requests (`eth_call`, `eth_getCode`, `eth_getStorageAt`, `eth_getTransactionByHash`, `eth_getBlockByNumber`). They never sign or send a transaction.

## Sources

- Launch-deposit contract: https://explorer.rayls.com/address/0x5B9565e27F5d50B14D3f660799f87e829A53fab2
- Rayls launch blog: https://www.rayls.com/blog/first-vault-on-rayls-launch-deposits-open
- Rayls AMA, 20 Oct 2026: https://www.youtube.com/live/cRsydQpZYos (8:18 rewards, 22:08 lock, 34:56 my question, 35:04 to 35:50 answer)
- Lagoon docs: https://docs.lagoon.finance/vault/upgradability-and-opt-in-proxy
- L2BEAT Stages: https://l2beat.com/stages
- EIP-1967: https://eips.ethereum.org/EIPS/eip-1967
