# IMD Tools (TOOLS)

`src/IMDTools.sol:IMDTools` is an immutable ERC-20 token. Its constructor mints
exactly **1,000,000,000 TOOLS**, with **18 decimals**, to the immediate deployer
(`msg.sender`). The name is **IMD Tools** and the symbol is **TOOLS**.

## Contract behavior and assumptions

- `INITIAL_SUPPLY` is `1000000000000000000000000000` base units (`10^27`).
  One TOOLS is `10^18` base units. This is the only mint, performed in the constructor.
- Transfers deliver the full requested amount. There are no transfer fees, burns,
  rebases, recipient callbacks, exemptions, trading switches, or maximum-wallet rules.
- There is no owner, administrator, minter, pauser, blacklist, seizure function,
  upgrade mechanism, external initialization, or externally callable burn function.
  The deployer has the same rights as any other holder after construction.
- The standard ERC-20 API includes `name`, `symbol`, `decimals`, `totalSupply`,
  `balanceOf`, `transfer`, `approve`, `allowance`, and `transferFrom`.
  Successful writes return `true`; invalid operations revert with OpenZeppelin's
  ERC-6093 custom errors. Transfers and approvals emit their standard events.
- Zero-amount and self-transfers are supported. Transfers to the zero address and
  approvals to the zero address are rejected. A positive `transferFrom` always
  requires the caller's allowance, including when the caller is the token holder.
- `approve` replaces the previous allowance. Finite allowances decrease on spending;
  `type(uint256).max` is an unlimited allowance and is not decreased. This version
  emits `Approval` on `approve`, but not when `transferFrom` spends an allowance.
  Integrations should read `allowance` to obtain the current value.
- There are no external contract calls or chain-specific precompiles. The token
  does not depend on block numbers, timestamps, randomness, or price feeds.

## Build and test

Run from the repository root with Foundry and Solidity **0.8.26** installed:

```sh
forge build
FOUNDRY_FUZZ_SEED=0xe497c385931a2f78f12da90b61151000c3c69c94a03631ee6aeb449a151a5808 forge test
forge fmt --check
```

`foundry.toml` pins Solidity 0.8.26, the Paris EVM target, the optimizer at 200 runs,
and `bytecode_hash = "none"`. Paris avoids requiring newer EVM instructions for
this simple token. FFI is disabled and no filesystem permissions are granted.
No RPC, environment file, private key, or external service is needed for tests.
The fuzz seed above is supplied by the assignment; the tests themselves never
read or modify environment variables. Fuzz tests run 1,024 cases each; the stateful
suite checks both invariants over 128 sequences of up to 64 actions.

OpenZeppelin Contracts **v5.0.2** (the ERC-20 import closure) and forge-std
**v1.9.7** (test utilities) are vendored as ordinary files under `lib/`, with their
licenses. A clean checkout builds without downloading dependencies when the pinned
compiler and Foundry are installed. See [DEPENDENCIES.md](DEPENDENCIES.md) for
upstream provenance and archive checksums. No submodules or package manager are used.

Tests cover metadata, the mint event, CREATE and CREATE2 factory deployment,
exact distribution and claim transfers, transfer events and edge cases,
approvals/revocation, finite and unlimited allowances, unauthorized spending,
revert atomicity, and absent mint/admin/upgrade entrypoints. Fuzz tests exercise
amounts and recipients; stateful tests compare balances and allowances with an
independent ledger through successful and rejected operation sequences.

Local verification with Foundry 1.8.4 and Solidity 0.8.26 passed `forge build`,
the seeded `forge test`, and `forge fmt --check`. Foundry reported 32 passing tests:
31 unit/fuzz tests and one grouped invariant suite containing two invariants
(8,192 handler calls, no unexpected reverts). The same checks passed in a fresh
temporary copy containing only `src/`, `test/`, `lib/`, and the build configuration,
with offline builds/tests and an environment containing only the executable path
and the specified fuzz seed.

The launch-flow test models token movements only. It is not a Uniswap v4 pool,
pricing, swap, or live-chain integration test. The supplied protected integration
suite belongs to the independent launch verifier; its factory, v4 contracts,
environment, and manifest are not part of this repository's local test fixtures.

## Deployment parameters

| Parameter | Value |
| --- | --- |
| Solidity identifier | `IMDTools` |
| Artifact | `out/IMDTools.sol/IMDTools.json` |
| Constructor arguments | None (`[]`) |
| Constructor value | Zero; the constructor is nonpayable |
| Name / symbol / decimals | `IMD Tools` / `TOOLS` / `18` |
| Total supply in base units | `1000000000000000000000000000` |
| Initial recipient | The immediate deploying address (`msg.sender`) |
| Intended chain from the assignment | Robinhood Chain, chain ID `4663` |
| Application contracts | None |
| Post-deployment initialization | None |

For the specified launch, the factory creates the token and receives **all** the
supply. A direct wallet deployment would instead credit that wallet. A helper
contract deployment credits the helper; the launch operator must use the intended
factory, not an intermediate deployment helper. `tx.origin` is never used.

The separate launch system supplies the factory, distributor, pool, and deployment
salt. No such address is hardcoded or required as a token constructor argument.
There are no linked libraries, proxies, hooks, or additional launch contracts in
this deliverable. The launch system writes `launch.json` after acceptance.

The following launch inputs are copied from the assignment for the manifest and
launch operator; they are **not token settings or independently verified live-chain
facts**:

| Launch input | Assignment value |
| --- | --- |
| Paired currency | IMD, `0x5f7bb59365ce557c26dbcaa4ee9d39a4b95b7127` (18 decimals) |
| Pool fee | `12500` (1.25%, a pool fee, not a token transfer fee) |
| Tick spacing | `60` |
| Initial price provenance | `79228162514264337593543950336` |
| `economics.poolBps` | `8800` |
| `economics.initialMarketCapWei` | `2500000000000000000000` (2,500 IMD) |
| `economics.remainderTo` | `0x667dde67817225159f08e34b836ce1a7f669c028` |

The factory distributes 10% (100,000,000 TOOLS) to the launch's MerkleDistributor,
allocates 88% (880,000,000 TOOLS) to the pool, and forwards 2% (20,000,000 TOOLS)
to the specified remainder recipient. These operations happen after the single
constructor mint and do not reserve tokens inside this contract. The launch
deployer derives the opening pool price from the market cap, supply, and token
address; the provenance price above is not a price enforced by the token.

## After launch and operational responsibilities

There are no token settings to configure, admin keys to assign, roles to renounce,
or maintenance transactions to run. Holders control their balances and grant
spending permissions through `approve`.

The launch operator is responsible for deploying the reviewed artifact through
the factory on the intended chain, checking metadata and the full constructor
mint, performing the launch distribution and pool setup, publishing the deployed
address, and verifying the source and compiler settings on the chain's explorer.
This repository does not broadcast transactions or provide wallet credentials.

Wallets and integrations must handle 18-decimal units, check transaction success,
and use the deployed address from the launch system. Holders should approve only
trusted spenders and revoke unused permissions. Changing a nonzero allowance has
the standard ERC-20 transaction-ordering race; setting it to zero and confirming
revocation before granting a replacement limits that risk.

The token cannot recover assets sent to the wrong address or to its own address.
There is no asset rescue function. It cannot accept ordinary native-token payments,
and any native currency forced into it is also unrecoverable. Immutability means
there is no administrative patch or emergency freeze. Chain execution, availability,
and finality remain assumptions of the launch infrastructure.

Local checks and the supplied security/L2 references inform implementation and
review, but do not constitute an independent security audit. An independent
adversarial review and the protected launch integration checks remain the launch
process's responsibility. No live-chain test, Slither, or Mythril run is claimed.
