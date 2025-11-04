// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/*
 * @titel DSCEngine
 * @author Rajib Kumar Pradhan
 *
 * The system is designed to be as minimal as possible to, and have the token maintain 1 token == $1 peg.
 * This stablecoin has the properties:
 * - Exogenous Collateral (ETH & BTC)
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was only backed by WETH & WBTC.
 *
 * Our DSC system should always be "overcollateralized" at no point, should the value of all collateral <= the value of all DSC.
 *
 * @notice This contract is the core of the DSC system. It handles all the logic for minting and redeeming DSC, as well as depositing & withdrawing collateral.
 * @notice This contract is very loosely based on the MakerDAO DSS (DAI) system.
 *
 */

contract DSCEngine is ReentrancyGuard {
    /////////////////
    // error       //
    /////////////////
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressAndPriceFeedAddressMustBeSame();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__transferFailed();

    ///////////////////////
    // State Variables   //
    ///////////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amourntDscMinted) private s_DSCMinted;
    address[] private s_collatoralTokens;

    ///////////////////////////
    // Immutable Variables   //
    ///////////////////////////
    DecentralizedStableCoin private immutable i_dsc;

    event CollatoralDepositreda(address indexed user, address indexed token, uint256 indexed amount);

    /////////////////
    // Modifiers   //
    /////////////////
    modifier moreThanZero(uint256 amount) {
        _moreThanZero(amount);
        _;
    }

    function _moreThanZero(uint256 amount) internal pure {
        if (amount <= 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
    }

    modifier isAllowedToken(address token) {
        _isAllowedToken(token);
        _;
    }

    function _isAllowedToken(address token) internal view {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
    }

    /////////////////
    // Functions   //
    /////////////////
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressAndPriceFeedAddressMustBeSame();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collatoralTokens.push(tokenAddresses[i]);
        }

        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    //////////////////////////
    // External Functions   //
    //////////////////////////
    function depositeCollatorallAndMintDsc() external {}

    /*
     * notice Follows CEI (Checks-Effects-Interactions) pattern
     * @param tokenCollatoralAddress The address of the collatoral token to deposite
     * @param amountCollatoral The amount of collatoral to deposite
     */
    function depositeCollatorall(address tokenCollatoralAddress, uint256 amountCollatoral)
        external
        moreThanZero(amountCollatoral)
        isAllowedToken(tokenCollatoralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollatoralAddress] += amountCollatoral;
        emit CollatoralDepositreda(msg.sender, tokenCollatoralAddress, amountCollatoral);
        bool success = IERC20(tokenCollatoralAddress).transferFrom(msg.sender, address(this), amountCollatoral);
        if (!success) {
            revert DSCEngine__transferFailed();
        }
    }

    function redeemCollatorallForDsc() external {}

    function redeemCollatorall() external {}

    /*
     * @notice Follows CEI (Checks-Effects-Interactions) pattern
     * @param amountDscToMint The amount of Decentralised Stable Coin to mint
     * @notice they must have more colatoral than the minimum threshold
     */
    function mintDsc(uint256 amountDscToMint) external moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        _reveetIfHealthFactorIsBroken(msg.sender);
    }

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external view returns (uint256) {}

    //////////////////////////////////////////
    // Private & Intaernal Veiw Functions   //
    //////////////////////////////////////////
    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 totalCollatoralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        totalCollatoralValueInUsd = getAccountCollatoralValueInUsd(user);
    }

    /*
     * @return the health factor of the user
     * @dev health factor = (total collatoral value in USD * liquidation threshold) / total DSC minted
     * - if health factor < 1, the user can be liquidated
     * - liquidation threshold is 50%, means that if the collatoral value drops by 50%, the user can be liquidated
     */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 totalCollatoralValueInUsd) = _getAccountInformation(user);
    }

    function _reveetIfHealthFactorIsBroken(address user) internal view {}

    /////////////////////////////////////////
    // Public & Intaernal Veiw Functions   //
    /////////////////////////////////////////

    function getAccountCollatoralValueInUsd(address user) public view returns (uint256 totalCollatoralValueInUsd) {
        for (uint256 i = 0; i < s_collatoralTokens.length; i++) {
            address token = s_collatoralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollatoralValueInUsd = getUsdValue(token, amount);
        }
        return totalCollatoralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price, , , ) = priceFeed.latestRoundData();

        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }
}
