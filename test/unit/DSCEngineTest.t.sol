// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address wbtc;

    address public USER = makeAddr("user");
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
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

    function test_DataStructuresAreProperlyUpdated() public {
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

    ////////////////////////////
    // redeemCollateral Tests //
    ////////////////////////////

    ///////////////////
    // mintDsc Tests //
    ///////////////////

    ///////////////////
    // burnDsc Tests //
    ///////////////////

    /////////////////////
    // liquidate Tests //
    /////////////////////

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
