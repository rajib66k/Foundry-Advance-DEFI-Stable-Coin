// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "../fuzz/Handler.t.sol";

contract OpenInvariantsTest is StdInvariant, Test {
    DeployDSC private deployer;
    DSCEngine private engine;
    DecentralizedStableCoin private dsc;
    HelperConfig private config;
    Handler private handler;

    address private weth;
    address private wbtc;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (,, weth, wbtc,) = config.activeNetworkConfig();
        // targetContract(address(engine)); // use fer openInvariant on DSCEngine directly
        handler = new Handler(engine, dsc);
        targetContract(address(handler));
    }

    function invariant_ProtocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(engine));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(engine));

        uint256 wethValue = engine.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = engine.getUsdValue(wbtc, totalWbtcDeposited);

        console.log("Total WETH Value in USD: ", wethValue);
        console.log("Total WBTC Value in USD: ", wbtcValue);
        console.log("Total Supply DSC: ", totalSupply);
        console.log("Times mintDsc called: ", handler.timesMintIsCalled());

        assert(wethValue + wbtcValue >= totalSupply);
    }
}
