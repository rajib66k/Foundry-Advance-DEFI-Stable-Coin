// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../Mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    DeployDSC private deployer;
    DSCEngine private engine;
    DecentralizedStableCoin private dsc;
    HelperConfig private config;

    address private USER = makeAddr("user");
    address private _USER = makeAddr("_user");

    address private wethUsdPriceFeed;
    address private wbtcUsdPriceFeed;
    address private weth;
    address private wbtc;

    uint256 private constant INITIAL_AMOUNT = 10 ether;
    uint256 private constant INITIAL_AMOUNT_USD = 1000 ether;
    uint256 private constant DEPOSIT_AMOUNT = 1 ether;
    uint256 private constant DEPOSIT_AMOUNT_USD = 100 ether;

    address[] private tokenAddresses;
    address[] private priceFeedAddresses;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc,) = config.activeNetworkConfig();
        deal(address(weth), USER, INITIAL_AMOUNT);
        deal(address(dsc), _USER, INITIAL_AMOUNT_USD);
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

    ////////////////////////////////
    // ReddemCollateral Tests     //
    ////////////////////////////////
    function testCanReedemCollateralIsSuccessful() public depositCollateral {
        uint256 REDEEMED_AMOUNT = 0.5 ether;
        vm.startPrank(USER);
        engine.redeemCollateral(weth, REDEEMED_AMOUNT);
        vm.stopPrank();

        uint256 expectedUserBalance = 0.5 ether;
        uint256 actualUserBalanceInUsd = engine.getAccountCollateralValueInUsd(USER);
        uint256 actualUserBalance = engine.getTokenAmountFromUsd(weth, actualUserBalanceInUsd);
        assertEq(expectedUserBalance, actualUserBalance);
    }

    function testRevertReddemCollateralIfHealthFactorIsBroken() public depositCollateral {
        uint256 dscToMint = 900 ether;
        uint256 REDEEMED_AMOUNT = 0.5 ether;
        uint256 LEFT_AMOUNT = 0.5 ether;
        uint256 expectedHealthFactor = engine.calculateHealthFactor(dscToMint, engine.getUsdValue(weth, LEFT_AMOUNT));
        vm.startPrank(USER);
        engine.mintDsc(dscToMint);
        vm.expectRevert(
            abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorIsBroken.selector, expectedHealthFactor)
        );
        engine.redeemCollateral(weth, REDEEMED_AMOUNT);
        vm.stopPrank();
    }

    ///////////////////////
    // MintDSC Tests     //
    ///////////////////////
    function testMintDscIsSuccessful() public depositCollateral {
        uint256 dscToMint = 100 ether;
        vm.startPrank(USER);
        engine.mintDsc(dscToMint);
        vm.stopPrank();

        uint256 expectedDscBalance = dscToMint;
        (uint256 actualDscBalance,) = engine.getAccountInformation(USER);
        assertEq(expectedDscBalance, actualDscBalance);
    }

    function testRevertMintDscIfHelthFactorIsBroken() public depositCollateral {
        uint256 dscToMint = 2000 ether;
        uint256 expectedHealthFactor =
            engine.calculateHealthFactor(dscToMint, engine.getAccountCollateralValueInUsd(USER));
        vm.startPrank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorIsBroken.selector, expectedHealthFactor)
        );
        engine.mintDsc(dscToMint);
        vm.stopPrank();
    }

    ///////////////////////
    // BurnDSC Tests     //
    ///////////////////////
    function testBurnDscIsSuccessful() public depositCollateral {
        uint256 dscToMint = 100 ether;
        uint256 dscToBurn = 90 ether;
        vm.startPrank(USER);
        engine.mintDsc(dscToMint);
        ERC20Mock(address(dsc)).approve(address(engine), dscToMint);
        engine.burnDsc(dscToBurn);
        vm.stopPrank();
        uint256 expectedDscBalance = dscToMint - dscToBurn;
        (uint256 actualDscBalance,) = engine.getAccountInformation(USER);
        assert(expectedDscBalance == actualDscBalance);
    }

    ////////////////////////////
    // HealthFactor Tests     //
    ////////////////////////////
    function testCalculateHealthFactorIsAccurate() public depositCollateral {
        uint256 dscToMint = 50 ether;
        uint256 collateralValueInUsd = engine.getAccountCollateralValueInUsd(USER);
        uint256 expectedHealthFactor = engine.calculateHealthFactor(dscToMint, collateralValueInUsd);

        vm.startPrank(USER);
        engine.mintDsc(dscToMint);
        uint256 actualHealthFactor = engine.calculateHealthFactor(dscToMint, collateralValueInUsd);
        vm.stopPrank();

        assertEq(expectedHealthFactor, actualHealthFactor);
    }

    ///////////////////////////
    // Liquidation Tests     //
    ///////////////////////////

    function testRevertLiquidationIfHealthFactorIsGood() public depositCollateral {
        uint256 dscToMint = 900 ether;
        uint256 dscToBurn = 100 ether;
        vm.startPrank(USER);
        engine.mintDsc(dscToMint);
        vm.stopPrank();
        vm.startPrank(_USER);
        ERC20Mock(address(dsc)).approve(address(engine), dscToBurn);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorIsGood.selector);
        engine.liquidate(weth, USER, dscToBurn);
        vm.stopPrank();
    }
}
