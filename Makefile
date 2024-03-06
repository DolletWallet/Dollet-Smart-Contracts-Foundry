-include .env

.PHONY: all test clean deploy-anvil coverage

COMMON_DEPLOYMENT_FLAGS := --rpc-url http://localhost:8545 --broadcast --optimizer-runs 8000 -vvv
# COMMON_DEPLOYMENT_FLAGS := --rpc-url ${RPC_AVAX_MAINNET} --broadcast --with-gas-price 40000000000 --verify --optimizer-runs 8000 --delay 10 --retries 10 -vvv

clean:; forge clean

build:; forge build

format:; forge fmt

size:; forge build --sizes --optimize --optimizer-runs 8000

coverage:; ./coverage.sh


# Run all tests with ``forge test`` or with the options below
test-strategies :; forge test --match-contract "(StrategyTest|StrategyPendleLSDTest|ARBGMXV2GLPStrategyTest|AVAXGMXV2GLPStrategyTest|ETHPendleeETHStrategyTest|ARBPendleeETHStrategyTest|WombatStrategyTest|ARBPendlesETHStrategyTest|AVAXsAvaxPoolWombatStrategy.t)" -vvv

test-vaults :; forge test --match-contract "(CompoundVault)" -vvv

test-calculations :; forge test --match-contract "(PendleLSDCalculationsTest|ARBGMXV2GLPCalculationsTest|AVAXGMXV2GLPCalculationsTest|WombatCalculationsTest)" -vvv

test-libraries :; forge test --match-contract "(ERC20LibTest|AddressUtilsTest)" -vvv

test-oracles :; forge test --match-contract "(OracleUniswapV3Test|OracleCurveTest|OracleBalancerWeightedTest|OracleCamelotV3Test|OracleCurveeETHTest|OracleCurveV2Test|OracleCurveWeETHTest|OracleTraderJoeV1Test)" -vvv

test-general :; forge test --match-contract "(FeeManagerTest|TemporaryAdminStructureTest|StrategyHelperTest|StrategyHelperVenueUniswapV2Test|StrategyHelperVenueUniswapV3Test|StrategyHelperVenueCurveTest|StrategyHelperVenueBalancerTest|StrategyHelperVenueCamelotV2Test|StrategyHelperVenueCamelotV3Test|StrategyHelperVenueFraxswapV2Test|StrategyHelperVenueTraderJoeV1Test)" -vvv


# Scripts
start-node :; anvil --fork-url ${RPC_AVAX_MAINNET}


# Deployment (general)
deploy-temporary-admin-structure:; forge script script/01_TemporaryAdminStructure.sol $(COMMON_DEPLOYMENT_FLAGS)
deploy-strategy-helper:; forge script script/02_StrategyHelper.sol $(COMMON_DEPLOYMENT_FLAGS)
deploy-fee-manager:; forge script script/03_FeeManager.sol $(COMMON_DEPLOYMENT_FLAGS)
deploy-strategy-helper-venue-uniswap-v3:; forge script script/04_StrategyHelperVenueUniswapV3.sol $(COMMON_DEPLOYMENT_FLAGS)
deploy-strategy-helper-venue-curve:; forge script script/05_StrategyHelperVenueCurve.sol $(COMMON_DEPLOYMENT_FLAGS)
deploy-strategy-helper-venue-balancer:; forge script script/06_StrategyHelperVenueBalancer.sol $(COMMON_DEPLOYMENT_FLAGS)
deploy-strategy-helper-venue-fraxswap-v2:; forge script script/07_StrategyHelperVenueFraxswapV2.sol $(COMMON_DEPLOYMENT_FLAGS)
deploy-strategy-helper-venue-camelot-v2:; forge script script/08_StrategyHelperVenueCamelotV2.sol $(COMMON_DEPLOYMENT_FLAGS)
deploy-strategy-helper-venue-camelot-v3:; forge script script/09_StrategyHelperVenueCamelotV3.sol $(COMMON_DEPLOYMENT_FLAGS)
deploy-strategy-helper-venue-traderjoe-v1:; forge script script/10_StrategyHelperVenueTraderJoeV1.sol $(COMMON_DEPLOYMENT_FLAGS)

# Pendle LSD strategy (OETH)
deploy-pendle-balancer-weighted-oracle:; forge script script/pendle-lsd/ETHoeth/01_PendleBalancerWeightedOracle.sol $(COMMON_DEPLOYMENT_FLAGS)
deploy-ETHoeth-curve-oracle:; forge script script/pendle-lsd/ETHoeth/02_OETHCurveOracle.sol $(COMMON_DEPLOYMENT_FLAGS)
deploy-pendle-lsd-calculations:; forge script script/pendle-lsd/ETHoeth/03_PendleLSDCalculations.sol $(COMMON_DEPLOYMENT_FLAGS)
deploy-pendle-lsd-strategy:; forge script script/pendle-lsd/ETHoeth/04_PendleLSDStrategy.sol $(COMMON_DEPLOYMENT_FLAGS)
deploy-pendle-lsd-vault:; forge script script/pendle-lsd/ETHoeth/05_PendleLSDVault.sol $(COMMON_DEPLOYMENT_FLAGS)


# Pendle LSD strategy (eETH - ETH)
deploy-pendle-eeth-balancer-weighted-oracle:; forge script script/pendle-lsd/ETHeeth/01_PendleBalancerWeightedOracle.sol $(COMMON_DEPLOYMENT_FLAGS)
deploy-eeth-curve-oracle:; forge script script/pendle-lsd/ETHeeth/02_EETHCurveOracle.sol $(COMMON_DEPLOYMENT_FLAGS)
deploy-weeth-curve-oracle:; forge script script/pendle-lsd/ETHeeth/03_WEETHCurveOracle.sol $(COMMON_DEPLOYMENT_FLAGS)
deploy-pendle-eeth-calculations:; forge script script/pendle-lsd/ETHeeth/04_PendleCalculations.sol $(COMMON_DEPLOYMENT_FLAGS)
deploy-pendle-eeth-strategy:; forge script script/pendle-lsd/ETHeeth/05_PendleStrategy.sol $(COMMON_DEPLOYMENT_FLAGS)
deploy-pendle-eeth-vault:; forge script script/pendle-lsd/ETHeeth/06_PendleVault.sol $(COMMON_DEPLOYMENT_FLAGS)

# Pendle LSD strategy (eETH - ARB)
deploy-pendle-pendle-weeth-uniswap-oracle:; forge script script/pendle-lsd/ARBeeth/01_PendleUniswapOracle.sol $(COMMON_DEPLOYMENT_FLAGS)
deploy-pendle-weeth-weth-uniswap-oracle:; forge script script/pendle-lsd/ARBeeth/02_WeethUniswapOracle.sol $(COMMON_DEPLOYMENT_FLAGS)
deploy-pendle-weeth-calculations:; forge script script/pendle-lsd/ARBeeth/03_PendleCalculations.sol $(COMMON_DEPLOYMENT_FLAGS)
deploy-pendle-weeth-strategy:; forge script script/pendle-lsd/ARBeeth/04_PendleStrategy.sol $(COMMON_DEPLOYMENT_FLAGS)
deploy-pendle-weeth-vault:; forge script script/pendle-lsd/ARBeeth/05_PendleVault.sol $(COMMON_DEPLOYMENT_FLAGS)

# Pendle LSD strategy (sETH - ARB)
deploy-pendle-pendle-seth-uniswap-oracle:; forge script script/pendle-lsd/ARBseth/01_PendleUniswapOracle.sol $(COMMON_DEPLOYMENT_FLAGS)
deploy-pendle-seth-calculations:; forge script script/pendle-lsd/ARBseth/02_PendleCalculations.sol $(COMMON_DEPLOYMENT_FLAGS)
deploy-pendle-seth-strategy:; forge script script/pendle-lsd/ARBseth/03_PendleStrategy.sol $(COMMON_DEPLOYMENT_FLAGS)
deploy-pendle-seth-vault:; forge script script/pendle-lsd/ARBseth/04_PendleVault.sol $(COMMON_DEPLOYMENT_FLAGS)

# GMX V2 GLP strategy
deploy-gmx-v2-glp-calculations:; forge script script/gmx-v2-glp/01_GMXV2GLPCalculations.sol $(COMMON_DEPLOYMENT_FLAGS)
deploy-gmx-v2-glp-strategy:; forge script script/gmx-v2-glp/02_GMXV2GLPStrategy.sol $(COMMON_DEPLOYMENT_FLAGS)
deploy-gmx-v2-glp-vault:; forge script script/gmx-v2-glp/03_GMXV2GLPVault.sol $(COMMON_DEPLOYMENT_FLAGS)


# Wombat strategy (frax - OP)
deploy-wombat-frax-calculations:; forge script script/wombat/OPfrax/01_WombatCalculations.sol $(COMMON_DEPLOYMENT_FLAGS)
deploy-wombat-frax-strategy:; forge script script/wombat/OPfrax/02_WombatStrategy.sol $(COMMON_DEPLOYMENT_FLAGS)
deploy-wombat-frax-vault:; forge script script/wombat/OPfrax/03_WombatVault.sol $(COMMON_DEPLOYMENT_FLAGS)

# Wombat strategy (avax - AVAX)
deploy-wombat-avax-traderjoe-oracle:; forge script script/wombat/AVAXavax/01_WomTraderJoeOracle.sol $(COMMON_DEPLOYMENT_FLAGS)
deploy-wombat-avax-calculations:; forge script script/wombat/AVAXavax/02_WombatCalculations.sol $(COMMON_DEPLOYMENT_FLAGS)
deploy-wombat-avax-strategy:; forge script script/wombat/AVAXavax/03_WombatStrategy.sol $(COMMON_DEPLOYMENT_FLAGS)
deploy-wombat-avax-vault:; forge script script/wombat/AVAXavax/04_WombatVault.sol $(COMMON_DEPLOYMENT_FLAGS)
