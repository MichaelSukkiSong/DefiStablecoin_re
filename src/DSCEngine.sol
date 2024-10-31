// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DSCEngine {
    ///////////////
    // errors    //
    ///////////////
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFaileD();

    ///////////////
    // Type      //
    ///////////////

    /////////////////////
    // State variables //
    /////////////////////

    mapping(address token => address priceFeed) private s_priceFeeds;
    address[] private s_collateralTokens;
    mapping(address user => mapping(address token => uint256)) private s_collateralDeposited;

    DecentralizedStableCoin private immutable i_dsc;

    ///////////////
    // events    //
    ///////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

    ///////////////
    // modifiers //
    ///////////////
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

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

    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFaileD();
        }
    }

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
