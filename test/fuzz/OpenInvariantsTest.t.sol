// // SPDX-License-Identifier: MIT
// pragma solidity 0.8.29;

// import {Test, console} from "forge-std/Test.sol";
// import {StdInvariant} from "forge-std/StdInvariant.sol";
// import {DeployDSC} from "../../script/DeployDSC.s.sol";
// import {DSCEngine} from "../../src/DSCEngine.sol";
// import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
// import {HelperConfig} from "../../script/HelperConfig.s.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// contract OpenInvariantsTest is StdInvariant, Test {
//     DeployDSC private deployer;
//     DSCEngine private engine;
//     DecentralizedStableCoin private dsc;
//     HelperConfig private config;

//     address private weth;
//     address private wbtc;

//     function setUp() public {
//         console.log("Starting setUp");

//         deployer = new DeployDSC();
//         console.log("DeployDSC created");

//         (dsc, engine, config) = deployer.run();
//         console.log("DeployDSC.run() completed");

//         (,, weth, wbtc,) = config.activeNetworkConfig();
//         console.log("Config loaded: WETH =", weth, "WBTC =", wbtc);

//         targetContract(address(engine));
//         console.log("Target contract set");
//     }

//     function invariant_ProtocolMustHaveMoreValueThanTotalSupply() public view {
//         uint256 totalSupply = dsc.totalSupply();
//         uint256 totalWethDeposited = IERC20(weth).balanceOf(address(engine));
//         uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(engine));

//         uint256 wethValue = engine.getUsdValue(weth, totalWethDeposited);
//         uint256 wbtcValue = engine.getUsdValue(wbtc, totalWbtcDeposited);

//         console.log("Total Supply DSC: ", totalSupply);
//         console.log("Total WETH Value in USD: ", wethValue);
//         console.log("Total WBTC Value in USD: ", wbtcValue);

//         assert(wethValue + wbtcValue >= totalSupply);
//     }
// }
