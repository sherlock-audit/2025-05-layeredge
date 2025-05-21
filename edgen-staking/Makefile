-include .env

build:; forge build

anvil: anvil

deploy-anvil: 
	@rm -rf out && forge script script/DeployLayerEdgeToken.s.sol:DeployLayerEdgeToken --rpc-url http://localhost:8545  \
		--private-key $(ANVIL_PRIVATE_KEY) --broadcast

deploy-token-base-sepolia: 
	@rm -rf out && forge script script/DeployLayerEdgeToken.s.sol:DeployLayerEdgeToken --rpc-url $(BASE_SEPOLIA_RPC_URL) \
		--private-key $(PRIVATE_KEY) --broadcast --verify
		--slow --etherscan-api-key $(BASE_SEPOLIA_API_KEY) -vvvv

deploy-weth9-base-sepolia:
	@rm -rf out && forge script script/DeployWETH9.s.sol:DeployWETH9 --rpc-url $(BASE_SEPOLIA_RPC_URL) \
		--private-key $(PRIVATE_KEY) --broadcast --verify --slow --etherscan-api-key $(BASESCAN_API_KEY) -vvvv

deploy-staking-base-sepolia:
	@rm -rf out && forge script script/DeployLayerEdgeStaking.s.sol:DeployLayerEdgeStaking --rpc-url $(BASE_SEPOLIA_RPC_URL) \
		--private-key $(PRIVATE_KEY) --broadcast --verify --slow --etherscan-api-key $(BASESCAN_API_KEY) -vvvv

deploy-token-edgen-testnet:
	@rm -rf out && forge script script/DeployLayerEdgeToken.s.sol:DeployLayerEdgeToken --rpc-url $(EDGEN_RPC_URL) \
		--private-key $(EDGEN_KEY) --broadcast

deploy-weth9-edgen-testnet:
	@rm -rf out && forge script script/DeployWETH9.s.sol:DeployWETH9 --rpc-url $(EDGEN_RPC_URL) \
		--private-key $(EDGEN_KEY) --broadcast --verify --slow --etherscan-api-key $(BASESCAN_API_KEY) -vvvv --verifier=blockscout \
		--verifier-url $(EDGEN_BLOCKSCOUT_URL)

deploy-staking-edgen-testnet:
	@rm -rf out && forge script script/DeployLayerEdgeStaking.s.sol:DeployLayerEdgeStaking --rpc-url $(EDGEN_RPC_URL) \
		--private-key $(EDGEN_KEY) --broadcast -vvvv

