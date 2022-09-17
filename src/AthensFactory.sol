// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import {AthensVoter} from "./AthensVoter.sol";
import {AthensVoterTokenERC20} from "./AthensVoterTokenERC20.sol";
import {GovernorBravoDelegateInterface} from "./interfaces/GovernorBravoDelegateInterface.sol";
import {AthensFactoryInterface} from "./interfaces/AthensFactoryInterface.sol";
import "openzeppelin/contracts/proxy/Clones.sol"
import {ERC20} from "solmate/tokens/ERC20.sol";

/*//////////////////////////////////////////////////////////////
                        ERRORS
//////////////////////////////////////////////////////////////*/
error NotBridge();
error InvalidAuxData();

/// @title AthensFactory
/// @author Maddiaa <Twitter: @Maddiaa0, Github: /cheethas>
contract AthensFactory is AthensFactoryInterface {
    address constant bridgeContractAddress = address(0xdead);

    // make immutable?
    AthensVoter public implementation;
    AthensVoterTokenERC20 public cloneErc20Implementation;

    uint64 public nextAvailableSlot;
    mapping(uint64 => AthensVoter) public voterProxies;
    mapping(address => AthensVoterTokenERC20) public syntheticVoterTokens;

    /*//////////////////////////////////////////////////////////////
                            MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier onlyBridge() {
        if (msg.sender != bridgeContractAddress) {
            revert NotBridge();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor() {
      // Init with dummy values
        implementation = new AthensVoter();
        implementation.initialize(address(this), address(0), address(0), 0, 0);

        // Init base erc20 token with dummy values
        cloneErc20Implementation = new AthensVoterTokenERC20();
        cloneErc20Implementation.initialize(address(this), "base", "BASE", 18);
    }

    /*//////////////////////////////////////////////////////////////
                            STATEFUL
    //////////////////////////////////////////////////////////////*/
    function createVoterProxy(address _tokenAddress, address _governorAddress, uint256 _proposalId, uint8 _vote)
        external
        returns (AthensVoter clone)
    {

        // Check if the underlying token has an erc20 token, if no create it.
        if (address(syntheticVoterTokens[_tokenAddress]) == address(0x0)) {
            syntheticVoterTokens[_tokenAddress] = createSyntheticVoterToken(_tokenAddress);
        }

        // init the clone
        bytes32 cloneHash = keccak256(abi.encodePacked(address(this), _governorAddress, _tokenAddress, _proposalId, _vote));
        clone = AthensVoter(Clones.cloneDeterministic(address(implementation), cloneHash));
        clone.initialize(address(this), _governorAddress, _tokenAddress, _proposalId, _vote);

        // cache next available slot in memory
        uint64 _nextAvailableSlot = nextAvailableSlot;
        voterProxies[_nextAvailableSlot] = clone;

        // Emit that a voter event is created for the front end
        emit CliesthenesVoterCreated(_nextAvailableSlot, _governorAddress, _proposalId, address(clone), _vote);

        // Increment the next available slot
        nextAvailableSlot = ++_nextAvailableSlot;
    }

    // Called by the bridge contract to get the proxy address of a vote - can only be called by the bridge
    /**
     * @param _auxData _aux bridge data, this tells us which voter proxy we are targeting
     * @param _totalInputValue The total number of input tokens being vote with
     */
    function allocateVote(uint64 _auxData, uint256 _totalInputValue) external onlyBridge {
        // TODO: receive the voting token and return an erc20 representing it to the shadow voter

        // Transfer the number of input tokens to the voter proxy
        // Store voter clone in memory
        AthensVoter voterClone = voterProxies[_auxData];

        // Revert if no proxy is deployed for the given aux data
        if (address(voterClone) == address(0x0)) revert InvalidAuxData();

        address _underlyingToken = voterClone.tokenAddress();

        // Send the underlying token to the voter proxy
        ERC20(_underlyingToken).transferFrom(address(bridgeContractAddress), address(voterClone), _totalInputValue);

        // Send the correct number of voter tokens to the bridge
        AthensVoterTokenERC20 _syntheticToken = syntheticVoterTokens[_underlyingToken];
        _syntheticToken.mint(msg.sender, _totalInputValue);
    }

    // TODO
    // function redeemVotingTokens(uint256 _totalInputValue) onlyBridge {
    //   // Return the number of voter tokens back to the bridge

    //   // Check that the factory has enough tokens to return to the bridge

    // }

    function returnUnderlyingToFactory(uint64 _proxyId) external {
        // If the vote has finished then return the tokens back to the factory so they can be withdrawn
    }

    // Call the comptroller contract and see if the vote has expired
    function hasVoteExpired(address _tokenAddress, uint256 _proposalId) external returns (bool validState) {
        GovernorBravoDelegateInterface.ProposalState returnedProposalState =
            GovernorBravoDelegateInterface(_tokenAddress).state(_proposalId);
        // TODO: more gas efficient way to do this?
        validState = (returnedProposalState == GovernorBravoDelegateInterface.ProposalState.Succeeded)
            || (returnedProposalState == GovernorBravoDelegateInterface.ProposalState.Expired)
            || (returnedProposalState == GovernorBravoDelegateInterface.ProposalState.Canceled)
            || (returnedProposalState == GovernorBravoDelegateInterface.ProposalState.Defeated)
            || (returnedProposalState == GovernorBravoDelegateInterface.ProposalState.Defeated);
    }

    // Deploy an erc20 factory to represent the tokens in the votes i.e. zkvComp, zkvUni
    function createSyntheticVoterToken(address _underlyingToken)
        internal
        returns (AthensVoterTokenERC20 voterToken)
    {
        // args
        bytes32 tokenHash = keccak256(abi.encode(_underlyingToken));

        // Get the name, symbol and decimals of the underlying
        string memory _name = string(abi.encodePacked("zkv", ERC20(_underlyingToken).name()));
        string memory _symbol = string(abi.encodePacked("zkv", ERC20(_underlyingToken).symbol()));
        uint8 decimals = ERC20(_underlyingToken).decimals();

        // deploy and initialised the erc20 implementation
        voterToken = AthensVoterTokenERC20(Clones.cloneDeterministic(address(cloneErc20Implementation), tokenHash));
        voterToken.initialize(address(this), _name, _symbol, decimals);

        // Emit an event as a new voter token has been created
        emit CliesthenesVoterTokenERC20Created(_underlyingToken, address(voterToken));
    }
}