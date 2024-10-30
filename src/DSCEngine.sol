// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";

contract DSCEngine {
    ///////////////
    // errors    //
    ///////////////
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();

    ///////////////
    // Type      //
    ///////////////

    /////////////////////
    // State variables //
    /////////////////////

    mapping(address token => address priceFeed) private s_priceFeeds;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;

    ///////////////
    // events    //
    ///////////////

    ///////////////
    // modifiers //
    ///////////////

    ///////////////
    // Functions //
    ///////////////

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ///////////////
    // external //
    ///////////////

    function depositCollateralAndMintDsc() external {}

    function redeemCollateralForDsc() external {}

    function liquidate() external {}

    ///////////////
    // public //
    ///////////////

    ///////////////
    // internal //
    ///////////////

    ///////////////
    // private //
    ///////////////

    ///////////////////////////
    // view & pure functions //
    ///////////////////////////
}
