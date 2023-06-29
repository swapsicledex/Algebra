// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import './libraries/Constants.sol';

import './interfaces/IAlgebraFactory.sol';
import './interfaces/IAlgebraPoolDeployer.sol';
import './interfaces/IAlgebraPluginFactory.sol';

import './AlgebraCommunityVault.sol';

import '@openzeppelin/contracts/access/Ownable2Step.sol';
import '@openzeppelin/contracts/access/AccessControlEnumerable.sol';

/// @title Algebra factory
/// @notice Is used to deploy pools and its plugins
/// @dev Version: Algebra V2.1
contract AlgebraFactory is IAlgebraFactory, Ownable2Step, AccessControlEnumerable {
  /// @inheritdoc IAlgebraFactory
  bytes32 public constant override POOLS_ADMINISTRATOR_ROLE = keccak256('POOLS_ADMINISTRATOR');

  /// @inheritdoc IAlgebraFactory
  address public immutable override poolDeployer;

  /// @inheritdoc IAlgebraFactory
  address public immutable override communityVault;

  /// @inheritdoc IAlgebraFactory
  uint16 public override defaultCommunityFee;

  /// @inheritdoc IAlgebraFactory
  uint16 public override defaultFee;

  /// @inheritdoc IAlgebraFactory
  int24 public override defaultTickspacing;

  /// @inheritdoc IAlgebraFactory
  uint256 public override renounceOwnershipStartTimestamp;

  /// @dev time delay before ownership renouncement can be finished
  uint256 private constant RENOUNCE_OWNERSHIP_DELAY = 1 days;

  // TODO
  IAlgebraPluginFactory public defaultPluginFactory;

  /// @inheritdoc IAlgebraFactory
  mapping(address => mapping(address => address)) public override poolByPair;

  constructor(address _poolDeployer) {
    require(_poolDeployer != address(0));
    poolDeployer = _poolDeployer;
    communityVault = address(new AlgebraCommunityVault());
    defaultTickspacing = Constants.INIT_DEFAULT_TICK_SPACING;
    defaultFee = Constants.BASE_FEE;
  }

  /// @inheritdoc IAlgebraFactory
  function owner() public view override(IAlgebraFactory, Ownable) returns (address) {
    return super.owner();
  }

  /// @inheritdoc IAlgebraFactory
  function hasRoleOrOwner(bytes32 role, address account) public view override returns (bool) {
    return (owner() == account || super.hasRole(role, account));
  }

  /// @inheritdoc IAlgebraFactory
  function defaultConfigurationForPool() external view returns (uint16 communityFee, int24 tickSpacing, uint16 fee) {
    return (defaultCommunityFee, defaultTickspacing, defaultFee);
  }

  /// @inheritdoc IAlgebraFactory
  function createPool(address tokenA, address tokenB) external override returns (address pool) {
    require(tokenA != tokenB);
    (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    require(token0 != address(0));
    require(poolByPair[token0][token1] == address(0));

    address defaultPlugin;
    if (address(defaultPluginFactory) != address(0)) {
      defaultPlugin = defaultPluginFactory.createPlugin(_computeAddress(token0, token1));
    }

    pool = IAlgebraPoolDeployer(poolDeployer).deploy(address(defaultPlugin), token0, token1);

    poolByPair[token0][token1] = pool; // to avoid future addresses comparison we are populating the mapping twice
    poolByPair[token1][token0] = pool;
    emit Pool(token0, token1, pool);
  }

  /// @inheritdoc IAlgebraFactory
  function setDefaultCommunityFee(uint16 newDefaultCommunityFee) external override onlyOwner {
    require(newDefaultCommunityFee <= Constants.MAX_COMMUNITY_FEE);
    require(defaultCommunityFee != newDefaultCommunityFee);
    defaultCommunityFee = newDefaultCommunityFee;
    emit DefaultCommunityFee(newDefaultCommunityFee);
  }

  /// @inheritdoc IAlgebraFactory
  function setDefaultFee(uint16 newDefaultFee) external override onlyOwner {
    require(newDefaultFee <= Constants.MAX_DEFAULT_FEE);
    require(defaultFee != newDefaultFee);
    defaultFee = newDefaultFee;
    emit DefaultFee(newDefaultFee);
  }

  /// @inheritdoc IAlgebraFactory
  function setDefaultTickspacing(int24 newDefaultTickspacing) external override onlyOwner {
    require(newDefaultTickspacing >= Constants.MIN_TICK_SPACING);
    require(newDefaultTickspacing <= Constants.MAX_TICK_SPACING);
    require(newDefaultTickspacing != defaultTickspacing);
    defaultTickspacing = newDefaultTickspacing;
    emit DefaultTickspacing(newDefaultTickspacing);
  }

  /// @inheritdoc IAlgebraFactory
  function setDefaultPluginFactory(address newDefaultPluginFactory) external override onlyOwner {
    require(newDefaultPluginFactory != address(defaultPluginFactory));
    defaultPluginFactory = IAlgebraPluginFactory(newDefaultPluginFactory);
    emit DefaultPluginFactory(newDefaultPluginFactory);
  }

  /// @inheritdoc IAlgebraFactory
  function startRenounceOwnership() external override onlyOwner {
    renounceOwnershipStartTimestamp = block.timestamp;
    emit RenounceOwnershipStart(renounceOwnershipStartTimestamp, renounceOwnershipStartTimestamp + RENOUNCE_OWNERSHIP_DELAY);
  }

  /// @inheritdoc IAlgebraFactory
  function stopRenounceOwnership() external override onlyOwner {
    require(renounceOwnershipStartTimestamp != 0);
    renounceOwnershipStartTimestamp = 0;
    emit RenounceOwnershipStop(block.timestamp);
  }

  /// @dev Leaves the contract without owner. It will not be possible to call `onlyOwner` functions anymore.
  /// Can only be called by the current owner if RENOUNCE_OWNERSHIP_DELAY seconds
  /// have passed since the call to the startRenounceOwnership() function.
  function renounceOwnership() public override onlyOwner {
    require(renounceOwnershipStartTimestamp != 0);
    require(block.timestamp - renounceOwnershipStartTimestamp >= RENOUNCE_OWNERSHIP_DELAY);
    renounceOwnershipStartTimestamp = 0;

    super.renounceOwnership();
    emit RenounceOwnershipFinish(block.timestamp);
  }

  /// @dev Transfers ownership of the contract to a new account (`newOwner`).
  /// Modified to fit with the role mechanism.
  function _transferOwnership(address newOwner) internal override {
    _revokeRole(DEFAULT_ADMIN_ROLE, owner());
    super._transferOwnership(newOwner);
    _grantRole(DEFAULT_ADMIN_ROLE, owner());
  }

  /// @dev keccak256 of AlgebraPool init bytecode. Used to compute pool address deterministically
  bytes32 private constant POOL_INIT_CODE_HASH = 0xaa0944c3fb626d40b58f9fa633fe20b67346bd966fa9c30739da526d2a04fe19;

  /// @notice Deterministically computes the pool address given the token0 and token1
  /// @param token0 first token
  /// @param token1 second token
  /// @return pool The contract address of the Algebra pool
  function _computeAddress(address token0, address token1) private view returns (address pool) {
    pool = address(uint160(uint256(keccak256(abi.encodePacked(hex'ff', poolDeployer, keccak256(abi.encode(token0, token1)), POOL_INIT_CODE_HASH)))));
  }
}
