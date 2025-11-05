// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDSC private deployer;
    DSCEngine private engine;
    DecentralizedStableCoin private dsc;
    HelperConfig private config;

    address private USER = makeAddr("user");

    address private wethUsdPriceFeed;
    address private wbtcUsdPriceFeed;
    address private weth;
    address private wbtc;

    uint256 private constant INITIAL_AMOUNT = 10 ether;
    uint256 private constant DEPOSIT_AMOUNT = 1 ether;

    address[] private tokenAddresses;
    address[] private priceFeedAddresses;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc,) = config.activeNetworkConfig();
        deal(address(weth), USER, INITIAL_AMOUNT);
        // ERC20Mock(weth).mint(USER, INITIAL_AMOUNT);
    }

    ///////////////////////////
    // Constructor Tests     //
    ///////////////////////////
    function testRevertIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(wethUsdPriceFeed);
        priceFeedAddresses.push(wbtcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressAndPriceFeedAddressMustBeSame.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    /////////////////////
    // Price Tests     //
    /////////////////////

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        uint256 ethPrice = 2000e8;

        uint256 expectedUsdValue = (ethAmount * ethPrice) / 1e8;
        uint256 actualUsdValue = engine.getUsdValue(weth, ethAmount);

        assertEq(expectedUsdValue, actualUsdValue);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100e18;
        uint256 ethPrice = 2000e8;

        uint256 expectedEthAmount = (usdAmount * 1e8) / ethPrice;
        uint256 actualEthAmount = engine.getTokenAmountFromUsd(weth, usdAmount);

        assertEq(expectedEthAmount, actualEthAmount);
    }

    //////////////////////////////////
    // DepositeCollateral Tests     //
    //////////////////////////////////

    function testRevertIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), DEPOSIT_AMOUNT);
        vm.stopPrank();

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
    }

    function testRevertWithUnapprovedCollateral() public {
        ERC20Mock testToken = new ERC20Mock();
        ERC20Mock(testToken).mint(USER, INITIAL_AMOUNT);

        vm.startPrank(USER);
        ERC20Mock(testToken).approve(address(engine), DEPOSIT_AMOUNT);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        engine.depositCollateral(address(testToken), DEPOSIT_AMOUNT);
        vm.stopPrank();
    }

    modifier depositCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), DEPOSIT_AMOUNT);
        engine.depositCollateral(weth, DEPOSIT_AMOUNT);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositCollateral {
        (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) = engine.getAccountInformation(USER);

        uint256 expectedDscMinted = 0;
        uint256 expectedDepositeAmount = engine.getTokenAmountFromUsd(weth, totalCollateralValueInUsd);
        assertEq(expectedDscMinted, totalDscMinted);
        assertEq(expectedDepositeAmount, DEPOSIT_AMOUNT);
    }
}
