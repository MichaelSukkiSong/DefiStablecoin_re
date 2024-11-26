// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

contract Handler is Test {
    DecentralizedStableCoin dsc;
    DSCEngine dsce;

    ERC20Mock weth;
    ERC20Mock wbtc;

    address[] public usersWithCollateralDeposited;
    MockV3Aggregator public ethUsdPriceFeed;

    uint256 constant MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        dsce = _dscEngine;
        dsc = _dsc;

        address[] memory collateralTokens = dsce.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethUsdPriceFeed = MockV3Aggregator(dsce.getPriceFeedAddress(address(weth)));
    }

    function depositCollateral(uint256 tokenCollateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getTokenCollateralFromSeed(tokenCollateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dsce), amountCollateral);
        dsce.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();

        usersWithCollateralDeposited.push(msg.sender);
    }

    function redeemCollateral(uint256 tokenCollateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getTokenCollateralFromSeed(tokenCollateralSeed);
        uint256 maxCollateralToRedeem = dsce.getCollateralBalanceOfUser(address(collateral), msg.sender);
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        if (amountCollateral == 0) {
            return;
        }

        dsce.redeemCollateral(address(collateral), amountCollateral);
    }

    function mintDsc(uint256 addressSeed, uint256 amoutDscToMint) public {
        if (usersWithCollateralDeposited.length == 0) {
            return;
        }

        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(sender);

        int256 maxDscToMint = int256(collateralValueInUsd / 2) - int256(totalDscMinted);
        if (maxDscToMint < 0) {
            return;
        }

        amoutDscToMint = bound(amoutDscToMint, 0, uint256(maxDscToMint));
        if (amoutDscToMint == 0) {
            return;
        }

        vm.startPrank(sender);
        dsce.mintDsc(amoutDscToMint);
        vm.stopPrank();
    }

    // function updateCollateralPrice(uint96 newPrice) public {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     ethUsdPriceFeed.updateAnswer(newPriceInt);
    // }

    //////////////////////
    // Helper functions //
    //////////////////////

    function _getTokenCollateralFromSeed(uint256 tokenCollateralSeed) public view returns (ERC20Mock) {
        if (tokenCollateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}
