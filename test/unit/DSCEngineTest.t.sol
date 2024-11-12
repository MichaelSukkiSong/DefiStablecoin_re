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

    address public USER = makeAddr("user");
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant AMOUNT_DSC_TO_MINT = 1 ether;

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

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

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

    function test_RevertsIfDebtToCoverIsZero() public {}

    function test_RevertsIfStartingUserHealthFactorIsLargerThanMinHealthFactor() public {}

    function test_ProperlyGetsTokenAmountFromUsd() public {}

    function test_ProperlyCalculatesTotalCollateralToRedeem() public {}

    function test_RedeemsCollateralFromUserToCaller() public {}

    function test_BurnsDscOnBehalfOfUserFromCaller() public {}

    function test_RevertsIfEndingUserHealthFactorIsSmallerThanStartingUserHealthFactor() public {}

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
