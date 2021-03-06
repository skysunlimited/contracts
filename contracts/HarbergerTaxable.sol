pragma solidity ^0.4.24;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";

contract HarbergerTaxable is Ownable {
  using SafeMath for uint256;

  uint256 public taxPercentage;
  address public taxCollector;
  address public ethFoundation;
  uint256 public currentFoundationContribution;
  uint256 public ethFoundationPercentage;
  uint256 public taxCollectorPercentage;

  event UpdateCollector(address indexed newCollector);
  event UpdateTaxPercentages(uint256 indexed newEFPercentage, uint256 indexed newTaxCollectorPercentage);

  constructor(uint256 _taxPercentage, address _taxCollector) public {
    taxPercentage = _taxPercentage;
    taxCollector = _taxCollector;
    ethFoundation = 0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359;
    ethFoundationPercentage = 20;
    taxCollectorPercentage = 80;
  }

  // The total self-assessed value of user's assets
  mapping(address => uint256) public valueHeld;

  // Timestamp for the last time taxes were deducted from a user's account
  mapping(address => uint256) public lastPaidTaxes;

  // The amount of ETH a user can withdraw at the last time taxes were deducted from their account
  mapping(address => uint256) public userBalanceAtLastPaid;

  /**
   * Modifiers
   */

  modifier hasPositveBalance(address user) {
    require(userHasPositveBalance(user) == true, "User has a negative balance");
    _;
  }

  /**
   * Public functions
   */

  function updateCollector(address _newCollector)
    public
    onlyOwner
  {
    require(_newCollector != address(0));
    taxCollector == _newCollector;
    emit UpdateCollector(_newCollector);
  }

  function updateTaxPercentages(uint256 _newEFPercentage, uint256 _newTaxCollectorPercentage)
    public
    onlyOwner
  {
    require(_newEFPercentage < 100);
    require(_newTaxCollectorPercentage < 100);
    require(_newEFPercentage.add(_newTaxCollectorPercentage) == 100);

    ethFoundationPercentage = _newEFPercentage;
    taxCollectorPercentage = _newTaxCollectorPercentage;
    emit UpdateTaxPercentages(_newEFPercentage, _newTaxCollectorPercentage);
  }

  function addFunds()
    public
    payable
  {
    userBalanceAtLastPaid[msg.sender] = userBalanceAtLastPaid[msg.sender].add(msg.value);
  }

  function withdraw(uint256 value) public onlyOwner {
    // Settle latest taxes
    require(transferTaxes(msg.sender, false), "User has a negative balance");

    // Subtract the withdrawn value from the user's account
    userBalanceAtLastPaid[msg.sender] = userBalanceAtLastPaid[msg.sender].sub(value);

    // Transfer remaining balance to msg.sender
    msg.sender.transfer(value);
  }

  function userHasPositveBalance(address user) public view returns (bool) {
    return userBalanceAtLastPaid[user] >= _taxesDue(user);
  }

  function userBalance(address user) public view returns (uint256) {
    return userBalanceAtLastPaid[user].sub(_taxesDue(user));
  }

  // Transfers the taxes a user owes from their account to the taxCollector and resets lastPaidTaxes to now
  function transferTaxes(address user, bool isInAuction) public returns (bool) {

    if (isInAuction) {
      return true;
    }

    uint256 taxesDue = _taxesDue(user);

    // Make sure the user has enough funds to pay the taxesDue
    if (userBalanceAtLastPaid[user] < taxesDue) {
        return false;
    }

    // Transfer taxes due from this contract to the tax collector
    _payoutTaxes(taxesDue);
    // Update the user's lastPaidTaxes
    lastPaidTaxes[user] = now;
    // subtract the taxes paid from the user's balance
    userBalanceAtLastPaid[user] = userBalanceAtLastPaid[user].sub(taxesDue);

    return true;
  }

  function payoutEF()
    public
  {
    uint256 uincornsRequirement = 2.014 ether;
    require(currentFoundationContribution >= uincornsRequirement);

    currentFoundationContribution = currentFoundationContribution.sub(uincornsRequirement);
    ethFoundation.transfer(uincornsRequirement);
  }

  /**
   * Internal functions
   */

  function _payoutTaxes(uint256 _taxesDue)
    internal
  {
    uint256 foundationContribution = _taxesDue.mul(ethFoundationPercentage).div(100);
    uint256 taxCollectorContribution = _taxesDue.mul(taxCollectorPercentage).div(100);

    currentFoundationContribution += foundationContribution;

    taxCollector.transfer(taxCollectorContribution);
  }

  // Calculate taxes due since the last time they had taxes deducted
  // from their account or since they bought their first token.
  function _taxesDue(address user) internal view returns (uint256) {
    // Make sure user owns tokens
    if (lastPaidTaxes[user] == 0) {
      return 0;
    }

    uint256 timeElapsed = now.sub(lastPaidTaxes[user]);
    return (valueHeld[user].mul(timeElapsed).div(365 days)).mul(taxPercentage).div(100);
  }

  function _addToValueHeld(address user, uint256 value) internal {
    require(transferTaxes(user, false), "User has a negative balance");
    require(userBalanceAtLastPaid[user] > 0);
    valueHeld[user] = valueHeld[user].add(value);
  }

  function _subFromValueHeld(address user, uint256 value, bool isInAuction) internal {
    require(transferTaxes(user, isInAuction), "User has a negative balance");
    valueHeld[user] = valueHeld[user].sub(value);
  }
}
