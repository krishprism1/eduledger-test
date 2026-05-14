## Documentation

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```



```shell
$ forge script script/Deploy.s.sol:Deploy \
  --rpc-url https://forno.celo-sepolia.celo-testnet.org \
  --broadcast \
  -vvvv
```

### Deploy
forge verify-contract \
  --chain-id 11142220 \
  --watch \
  $SMART_CONTRACT_ADDRESS \
  src/EduLedgerNFT.sol:EduLedgerNFT \
  $ETHERSCAN_API_KEY

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```


- deployed smart contract https://sepolia.celoscan.io/address/0xbd517dfba8b762bc7681a7fbbf00dc562cf916d1


