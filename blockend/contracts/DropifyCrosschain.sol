
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import "./interface/IVault.sol";
import "./StructsAndErrors.sol";

contract DropifyCrosschain is CCIPReceiver {
    
    struct ConstructorParams{
        uint64 chainId;
        uint64 coreChainId;
        address coreAddress;
        uint64 coreSelector;
        address vaultImplementation;
        address ccipRouter;
    }
    mapping(uint256 => CrosschainAirdrop) public airdrops;
    mapping(uint256=>mapping(uint256=>bool)) public nullifiers;
    uint256 public localAirdropIds;
    address public owner;
    address public vaultImplementation;
    uint64 public chain;

    address public coreAddress;
    uint64 public coreSelector;
    uint64 public coreChain;
    uint64 public coreHyperlaneSelector;
    bytes4 public constant INITIALIZE_VAULT_METHOD_ID=bytes4(keccak256("initialize(address,address,uint256,uint256,string)"));

    constructor(ConstructorParams memory params) CCIPReceiver(params.ccipRouter){
        localAirdropIds = 0;
        owner = msg.sender;
        chain = params.chainId;
        coreAddress = params.coreAddress;
        coreSelector = params.coreSelector;
        coreChain = params.coreChainId;
        vaultImplementation = params.vaultImplementation;
    }

    event AirdropCrosschainCreated(uint256 localAirdropId, bytes32 crosschainMessageId, address creator, address vaultAddress, uint256 tokenAmount, uint256 tokensPerClaim, string metadata);
    event AidropClaimed(uint256 airdropId, address claimerAddress, uint256 nullifierHash, uint256 amountClaimed);

    modifier onlyOwner{
        if(msg.sender != owner){
            revert NotOwner(msg.sender);
        }
        _;
    }

    modifier onlyAuthorizedCrosschain(address _caller, uint64 _chain ){
       if(coreAddress != _caller || coreSelector != _chain) revert NotAuthorizedCrosschain(_chain, _caller);
        _;
    }

    function createAirdrop(CreateAirdropParams memory params) external payable{
        if(IERC20(params.tokenAddress).allowance(msg.sender, address(this)) < params.tokenAmount) revert NotEnoughAllowance(params.tokenAmount);

        address vaultAddress = _deployProxy(vaultImplementation, localAirdropIds);
        bytes memory initData = abi.encodeWithSelector(
            INITIALIZE_VAULT_METHOD_ID,
            params.tokenAddress,
            address(this),
            params.tokenAmount,
            params.tokensPerClaim,
            params.metadata
        );
        (bool success, ) = vaultAddress.call(initData);
        if(!success) revert VaultInitFailed(vaultAddress);

        IERC20(params.tokenAddress).transferFrom(msg.sender, vaultAddress, params.tokenAmount);

        airdrops[localAirdropIds] = CrosschainAirdrop({
            chainId: chain,
            localAirdropId: localAirdropIds,
            creator: msg.sender,
            tokenAddress: params.tokenAddress,
            tokenAmount: params.tokenAmount,
            tokensPerClaim: params.tokensPerClaim,
            tokensClaimed: 0,
            vaultAddress: vaultAddress,
            metadata: params.metadata
        });

        bytes memory _data=abi.encode(airdrops[localAirdropIds]);
       
        bytes32 crosschainMessageId = _sendMessagePayNative(msg.value, _data);

        emit AirdropCrosschainCreated(localAirdropIds, crosschainMessageId, msg.sender, vaultAddress, params.tokenAmount, params.tokensPerClaim, params.metadata);
        localAirdropIds++;
    }

    function _sendMessagePayNative(uint256 _feePaid, bytes memory _data) internal returns (bytes32 messageId)
    {
        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(_data);
        IRouterClient router = IRouterClient(this.getRouter());
        uint256 fees = router.getFee(coreSelector, evm2AnyMessage);

        if (fees > _feePaid)
            revert NotEnoughCrosschainFee(_feePaid, fees);

        messageId = router.ccipSend{value: _feePaid}(
            coreSelector,
            evm2AnyMessage
        );

        return messageId;
        
    }

    function _ccipReceive(
        Client.Any2EVMMessage memory any2EvmMessage
    )
        internal
        override
          onlyAuthorizedCrosschain(
            abi.decode(any2EvmMessage.sender, (address)),
            any2EvmMessage.sourceChainSelector
        )
    {
        CrosschainClaim memory claim = abi.decode(any2EvmMessage.data, (CrosschainClaim));
        if(nullifiers[claim.localAirdropId][claim.nullifier]) revert HumanAlreadyClaimed(claim.localAirdropId, claim.nullifier);
        nullifiers[claim.localAirdropId][claim.nullifier] = true;

        CrosschainAirdrop memory airdrop = airdrops[claim.localAirdropId];
        if(airdrop.tokensClaimed + airdrop.tokensPerClaim > airdrop.tokenAmount) revert VaultDepleted(claim.localAirdropId, airdrop.tokensClaimed, airdrop.tokensPerClaim, airdrop.tokenAmount);
        airdrops[claim.localAirdropId].tokensClaimed += airdrop.tokensPerClaim;

        IVault(airdrop.vaultAddress).releaseTokens(claim.claimer, airdrop.tokensPerClaim);
        emit AidropClaimed(claim.localAirdropId, claim.claimer, claim.nullifier, airdrop.tokensPerClaim);      
    }

    function _buildCCIPMessage(
        bytes memory _data
    ) private view returns (Client.EVM2AnyMessage memory) {
        return
            Client.EVM2AnyMessage({
                receiver: abi.encode(coreAddress),
                data: _data, 
                tokenAmounts: new Client.EVMTokenAmount[](0), 
                extraArgs: Client._argsToBytes(
                    Client.EVMExtraArgsV1({gasLimit: 800_000})
                ),
                feeToken: address(0)
            });
    }

    function _deployProxy(
        address implementation,
        uint salt
    ) internal returns (address _contractAddress) {
        bytes memory code = _creationCode(implementation, salt);
        _contractAddress = Create2.computeAddress(
            bytes32(salt),
            keccak256(code)
        );
        if (_contractAddress.code.length != 0) return _contractAddress;

        _contractAddress = Create2.deploy(0, bytes32(salt), code);
    }

    function _creationCode(
        address implementation_,
        uint256 salt_
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                hex"3d60ad80600a3d3981f3363d3d373d3d3d363d73",
                implementation_,
                hex"5af43d82803e903d91602b57fd5bf3",
                abi.encode(salt_)
            );
    }

    function getFee(CrosschainAirdrop memory params) external view returns (uint256){
        bytes memory _data=abi.encode(params);
        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(_data);
        IRouterClient router = IRouterClient(this.getRouter());
        return router.getFee(coreSelector, evm2AnyMessage);
    }

}