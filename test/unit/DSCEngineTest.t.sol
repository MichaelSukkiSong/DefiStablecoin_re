// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockFailedTransferFrom} from "../mocks/MockFailedTransferFrom.sol";
import {MockFailedTransfer} from "../mocks/MockFailedTransfer.sol";
import {MockFailedMintDSC} from "../mocks/MockFailedMintDSC.sol";
import {MockFailedTransferFromDSC} from "../mocks/MockFailedTransferFromDSC.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {MockMoreDebtDSC} from "../mocks/MockMoreDebtDSC.sol";

contract DSCEngineTest is Test {
    DeployDSC deploydsc;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;

    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address wbtc;
    address deployer;

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");

    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant AMOUNT_DSC_TO_MINT = 1 ether;
    uint256 public constant AMOUNT_COLLATERAL_LIQUIDATEABLE = 0.1 ether;
    uint256 public constant AMOUNT_COLLATERAL_LIQUIDATOR = 0.2 ether;
    uint256 public constant STARTING_ERC20_BALANCE_LIQUIDATOR = 0.2 ether;

    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10;

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    function setUp() external {
        deploydsc = new DeployDSC();
        (dsc, dsce, config) = deploydsc.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, deployer) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(wbtc).mint(USER, STARTING_ERC20_BALANCE);
    }

    ///////////////////////
    // Constructor Tests //
    ///////////////////////

    function test_RevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    function test_CollateralDepositedDataStructuresAreProperlyAdded() public {
        tokenAddresses.push(weth);
        tokenAddresses.push(wbtc);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        DSCEngine engine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));

        assertEq(engine.getPriceFeedAddress(weth), ethUsdPriceFeed);
        assertEq(engine.getPriceFeedAddress(wbtc), btcUsdPriceFeed);

        assertEq(engine.getCollateralTokens()[0], weth);
        assertEq(engine.getCollateralTokens()[1], wbtc);

        assert(engine.getDSC() == DecentralizedStableCoin(address(dsc)));
    }

    /////////////////////////////
    // depositCollateral Tests //
    /////////////////////////////

    function test_RevertsIfDepositCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function test_RevertsWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dsce.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function test_CanDepositedCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);

        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd);

        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    function test_DataStructureIsProperlyUpdated() public depositedCollateral {
        assertEq(dsce.getCollateralBalanceOfUser(USER, weth), AMOUNT_COLLATERAL);
    }

    function test_EmitsCollateralDepositedEvent() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        vm.expectEmit(true, true, true, false);
        emit CollateralDeposited(USER, weth, AMOUNT_COLLATERAL);

        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function test_TokenTransferIsCorrect() public depositedCollateral {
        assertEq(ERC20Mock(weth).balanceOf(USER), STARTING_ERC20_BALANCE - AMOUNT_COLLATERAL);
        assertEq(ERC20Mock(weth).balanceOf(address(dsce)), AMOUNT_COLLATERAL);
    }

    // this test needs it's own setup - MockFailedTransferFrom.sol
    function test_RevertsIfTransferFromFailsWhenDepositingCollateral() public {
        // Arrange - Setup
        address owner = msg.sender;
        vm.prank(owner);
        MockFailedTransferFrom mockDsc = new MockFailedTransferFrom();

        tokenAddresses = [address(mockDsc)];
        priceFeedAddresses = [ethUsdPriceFeed];

        vm.prank(owner);
        DSCEngine mockDsce = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));
        mockDsc.mint(USER, AMOUNT_COLLATERAL);

        vm.prank(owner);
        mockDsc.transferOwnership(address(mockDsce));

        // Arrange - User
        vm.startPrank(USER);
        ERC20Mock(address(mockDsc)).approve(address(mockDsce), AMOUNT_COLLATERAL);
        // Act / Assert
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockDsce.depositCollateral(address(mockDsc), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    ////////////////////////////
    // redeemCollateral Tests //
    ////////////////////////////

    function test_RevertsIfRedeemCollateralZero() public depositedCollateral {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function test_CollateralDepositedDataStructuresAreProperlyDecreased() public depositedCollateral {
        vm.startPrank(USER);
        dsce.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        assertEq(dsce.getCollateralBalanceOfUser(USER, weth), 0);
    }

    function test_EmitsCollateralRedeemedEvent() public depositedCollateral {
        vm.startPrank(USER);
        vm.expectEmit(true, true, true, false);
        emit CollateralRedeemed(USER, USER, weth, AMOUNT_COLLATERAL);
        dsce.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier redeemedCollateral() {
        vm.startPrank(USER);
        dsce.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function test_TokenIsTransferedCorrectly() public depositedCollateral redeemedCollateral {
        assertEq(ERC20Mock(weth).balanceOf(USER), STARTING_ERC20_BALANCE);
        assertEq(ERC20Mock(weth).balanceOf(address(dsce)), 0);
    }

    function test_RevertsIfTransferFails() public {
        // Arrange - Setup
        address owner = msg.sender;
        vm.prank(owner);
        MockFailedTransfer mockDsc = new MockFailedTransfer();

        tokenAddresses = [address(mockDsc)];
        priceFeedAddresses = [ethUsdPriceFeed];

        vm.prank(owner);
        DSCEngine mockDsce = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));
        mockDsc.mint(USER, AMOUNT_COLLATERAL);

        vm.prank(owner);
        mockDsc.transferOwnership(address(mockDsce));

        // Arrange - User
        vm.startPrank(USER);
        ERC20Mock(address(mockDsc)).approve(address(mockDsce), AMOUNT_COLLATERAL);
        mockDsce.depositCollateral(address(mockDsc), AMOUNT_COLLATERAL);
        vm.stopPrank();

        // Act / Assert
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockDsce.redeemCollateral(address(mockDsc), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    ///////////////////
    // mintDsc Tests //
    ///////////////////

    function test_AmountDscToMintIsMoreThanZero() public depositedCollateral {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.mintDsc(0);
        vm.stopPrank();
    }

    function test_DSCMintedDataStructuresAreProperlyUpdated() public depositedCollateral {
        vm.startPrank(USER);
        dsce.mintDsc(AMOUNT_DSC_TO_MINT);
        vm.stopPrank();

        assertEq(dsce.getDSCMintedAmountOfUser(USER), AMOUNT_DSC_TO_MINT);
    }

    modifier mintedDsc() {
        vm.startPrank(USER);
        dsce.mintDsc(AMOUNT_DSC_TO_MINT);
        vm.stopPrank();
        _;
    }

    function test_DscIsProperlyMinted() public depositedCollateral mintedDsc {
        assertEq(ERC20Mock(address(dsc)).balanceOf(USER), AMOUNT_DSC_TO_MINT);
    }

    function test_RevertsIfMintDscFails() public {
        // Arrange - Setup
        address owner = msg.sender;
        vm.prank(owner);
        MockFailedMintDSC mockDsc = new MockFailedMintDSC();

        tokenAddresses = [address(mockDsc)];
        priceFeedAddresses = [ethUsdPriceFeed];

        vm.prank(owner);
        DSCEngine mockDsce = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));

        vm.prank(owner);
        mockDsc.mint(USER, AMOUNT_COLLATERAL);

        vm.prank(owner);
        mockDsc.transferOwnership(address(mockDsce));

        // Arrange - User
        vm.startPrank(USER);
        ERC20Mock(address(mockDsc)).approve(address(mockDsce), AMOUNT_COLLATERAL);
        mockDsce.depositCollateral(address(mockDsc), AMOUNT_COLLATERAL);
        vm.stopPrank();

        // Act / Assert
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
        mockDsce.mintDsc(AMOUNT_DSC_TO_MINT);
        vm.stopPrank();
    }

    function testRevertsIfMintAmountBreaksHealthFactor() public depositedCollateral {
        uint256 amountToMint;

        (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        amountToMint = (AMOUNT_COLLATERAL * (uint256(price) * dsce.getAdditionalFeedPrecision())) / dsce.getPrecision();

        vm.startPrank(USER);
        uint256 expectedHealthFactor =
            dsce.calculateHealthFactor(amountToMint, dsce.getUsdValue(weth, AMOUNT_COLLATERAL));

        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        dsce.mintDsc(amountToMint);
        vm.stopPrank();
    }

    ///////////////////
    // burnDsc Tests //
    ///////////////////

    function test_AmountDscToBurnIsMoreThanZero() public depositedCollateral mintedDsc {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.burnDsc(0);
        vm.stopPrank();
    }

    function test_DSCMintedDataStructureIsProperlyDecreased() public depositedCollateral mintedDsc {
        vm.startPrank(USER);
        DecentralizedStableCoin(dsc).approve(address(dsce), AMOUNT_DSC_TO_MINT);
        dsce.burnDsc(AMOUNT_DSC_TO_MINT);
        vm.stopPrank();

        assertEq(dsce.getDSCMintedAmountOfUser(USER), 0);
    }

    function test_TokenIsProperlyBurned() public depositedCollateral mintedDsc {
        vm.startPrank(USER);
        DecentralizedStableCoin(dsc).approve(address(dsce), AMOUNT_DSC_TO_MINT);
        dsce.burnDsc(AMOUNT_DSC_TO_MINT);
        vm.stopPrank();

        assertEq(ERC20Mock(address(dsc)).balanceOf(USER), 0);
    }

    function test_RevertsIfTokenTransferFromFailsWhenBurningDsc() public {
        // Arrange - Setup
        address owner = msg.sender;
        vm.prank(owner);
        MockFailedTransferFromDSC mockDsc = new MockFailedTransferFromDSC();

        tokenAddresses = [weth];
        priceFeedAddresses = [ethUsdPriceFeed];

        vm.prank(owner);
        DSCEngine mockDsce = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));

        vm.prank(owner);
        mockDsc.mint(USER, AMOUNT_COLLATERAL);

        vm.prank(owner);
        mockDsc.transferOwnership(address(mockDsce));

        // Arrange - User
        vm.startPrank(USER);
        ERC20Mock(address(weth)).approve(address(mockDsce), AMOUNT_COLLATERAL);
        mockDsce.depositCollateral(address(weth), AMOUNT_COLLATERAL);
        vm.stopPrank();

        vm.startPrank(USER);
        MockFailedTransferFromDSC(address(mockDsc)).approve(address(mockDsce), AMOUNT_DSC_TO_MINT);
        mockDsce.mintDsc(AMOUNT_DSC_TO_MINT);
        vm.stopPrank();

        // Act / Assert
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockDsce.burnDsc(AMOUNT_DSC_TO_MINT);
        vm.stopPrank();
    }

    /////////////////////
    // liquidate Tests //
    /////////////////////

    modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_TO_MINT);
        vm.stopPrank();
        _;
    }

    function test_RevertsIfDebtToCoverIsZero() public depositedCollateralAndMintedDsc {
        // "The crash"
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        // uint256 userHealthFactor = dsce.getHealthFactor(USER);

        ERC20Mock(weth).mint(LIQUIDATOR, AMOUNT_COLLATERAL);

        vm.startPrank(LIQUIDATOR);

        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_TO_MINT);

        dsc.approve(address(dsce), AMOUNT_DSC_TO_MINT);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.liquidate(weth, USER, 0);

        vm.stopPrank();
    }

    function test_RevertsIfStartingUserHealthFactorIsLargerThanMinHealthFactor() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_TO_MINT);
        vm.stopPrank();

        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        ERC20Mock(weth).mint(LIQUIDATOR, AMOUNT_COLLATERAL);

        vm.startPrank(LIQUIDATOR);

        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_TO_MINT);

        dsc.approve(address(dsce), AMOUNT_DSC_TO_MINT);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        dsce.liquidate(weth, USER, AMOUNT_DSC_TO_MINT);

        vm.stopPrank();
    }

    function test_ProperlyGetsTokenAmountFromUsd() public view {
        // If we want $100 of WETH @ $2000/WETH, that would be 0.05 WETH
        uint256 expectedWeth = 0.05 ether;
        uint256 amountWeth = dsce.getTokenAmountFromUsd(weth, 100 ether);
        assertEq(amountWeth, expectedWeth);
    }

    modifier liquidated() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL_LIQUIDATEABLE);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL_LIQUIDATEABLE, AMOUNT_DSC_TO_MINT);
        vm.stopPrank();

        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        // uint256 userHealthFactor = dsce.getHealthFactor(USER);

        ERC20Mock(weth).mint(LIQUIDATOR, STARTING_ERC20_BALANCE_LIQUIDATOR);

        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL_LIQUIDATOR);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL_LIQUIDATOR, AMOUNT_DSC_TO_MINT);
        dsc.approve(address(dsce), AMOUNT_DSC_TO_MINT);
        dsce.liquidate(weth, USER, AMOUNT_DSC_TO_MINT); // We are covering their whole debt
        vm.stopPrank();
        _;
    }

    function test_RedeemsCollateralFromUserToLiquidator() public liquidated {
        uint256 tokenAmountFromDebtCovered = dsce.getTokenAmountFromUsd(weth, AMOUNT_DSC_TO_MINT);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;

        assertEq(dsce.getCollateralBalanceOfUser(USER, weth), AMOUNT_COLLATERAL_LIQUIDATEABLE - totalCollateralToRedeem);
    }

    function test_BurnsDscOnBehalfOfUserFromCaller() public liquidated {
        assertEq(dsce.getDSCMintedAmountOfUser(USER), 0);
        assertEq(DecentralizedStableCoin(dsc).balanceOf(LIQUIDATOR), 0);
    }

    function test_RevertsIfEndingUserHealthFactorIsSmallerThanStartingUserHealthFactor() public {
        // Arrange - Setup
        MockMoreDebtDSC mockDsc = new MockMoreDebtDSC(ethUsdPriceFeed);
        tokenAddresses = [weth];
        priceFeedAddresses = [ethUsdPriceFeed];
        address owner = msg.sender;
        vm.prank(owner);
        DSCEngine mockDsce = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));
        mockDsc.transferOwnership(address(mockDsce));
        // Arrange - User
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(mockDsce), AMOUNT_COLLATERAL_LIQUIDATEABLE);
        mockDsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL_LIQUIDATEABLE, AMOUNT_DSC_TO_MINT);
        vm.stopPrank();

        // Arrange - Liquidator
        ERC20Mock(weth).mint(LIQUIDATOR, AMOUNT_COLLATERAL_LIQUIDATOR);

        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(mockDsce), AMOUNT_COLLATERAL_LIQUIDATOR);
        uint256 debtToCover = 0.1 ether;
        mockDsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL_LIQUIDATOR, AMOUNT_DSC_TO_MINT);
        mockDsc.approve(address(mockDsce), debtToCover);
        // Act
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        // Act/Assert
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorNotImproved.selector);
        mockDsce.liquidate(weth, USER, debtToCover);
        vm.stopPrank();
    }

    /////////////////////////////////////
    // price Tests //
    /////////////////////////////////////

    function test_GetUsdValue() public view {
        uint256 expectedUsdValue = 2000 * 10;
        uint256 usdValue = dsce.getUsdValue(weth, 10);
        assertEq(usdValue, expectedUsdValue);
    }

    ///////////////////////////////////////
    // depositCollateralAndMintDsc Tests //
    ///////////////////////////////////////

    function test_RevertsIfMintedDscBreaksHealthFactor() public {
        (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        uint256 amountCollateral = 10 ether;
        uint256 amountToMint;

        amountToMint = (amountCollateral * (uint256(price) * dsce.getAdditionalFeedPrecision())) / dsce.getPrecision();
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);

        uint256 expectedHealthFactor =
            dsce.calculateHealthFactor(amountToMint, dsce.getUsdValue(weth, amountCollateral));

        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        dsce.depositCollateralAndMintDsc(weth, amountCollateral, amountToMint);
        vm.stopPrank();
    }

    function test_CanMintWithDepositedCollateral() public depositedCollateralAndMintedDsc {
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, AMOUNT_DSC_TO_MINT);
    }

    ///////////////////////////////////
    // redeemCollateralForDsc Tests //
    //////////////////////////////////

    ////////////////////////
    // healthFactor Tests //
    ////////////////////////

    ///////////////////////////////////
    // View & Pure Function Tests //
    //////////////////////////////////

    /////////////////////////////////////
    // getAccountCollateralValue Tests //
    /////////////////////////////////////

    ///////////////////////
    // getUsdValue Tests //
    ///////////////////////

    /////////////////////////////////
    // getTokenAmountFromUsd Tests //
    /////////////////////////////////
}
