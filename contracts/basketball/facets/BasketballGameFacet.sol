// SPDX-License-Identifier: MIT
pragma solidity 0.8.3;

import {
    LibBasketball,
    NUMERIC_TRAITS_NUM,
    CardPackTraitsIO,
    InternalCardPackTraitsIO,
    PACK_CARDS_NUM
} from "../libraries/LibBasketball.sol";

import {LibAppStorage} from "../libraries/LibAppStorage.sol";

import {IERC20} from "../../shared/interfaces/IERC20.sol";
import {LibStrings} from "../../shared/libraries/LibStrings.sol";
import {Release, Card} from "../libraries/LibAppStorage.sol";
import {Modifiers} from "../miscellaneous/Modifiers.sol";
import {LibERC20} from "../../shared/libraries/LibERC20.sol";
// import "hardhat/console.sol";
import {CollateralEscrow} from "../CollateralEscrow.sol";
import {LibMeta} from "../../shared/libraries/LibMeta.sol";
import {LibERC721Marketplace} from "../libraries/LibERC721Marketplace.sol";

contract BasketballGameFacet is Modifiers {
    /// @dev This emits when the approved address for an NFT is changed or
    ///  reaffirmed. The zero address indicates there is no approved address.
    ///  When a Transfer event emits, this also indicates that the approved
    ///  address for that NFT (if any) is reset to none.

    /// @dev This emits when an operator is enabled or disabled for an owner.
    ///  The operator can manage all NFTs of the owner.

    event ClaimCard(uint256 indexed _tokenId);

    event SetCardName(uint256 indexed _tokenId, string _oldName, string _newName);

    event SetBatchId(uint256 indexed _batchId, uint256[] tokenIds);

    event SpendSkillPoints(uint256 indexed _tokenId, int16[4] _values);

    event LockCard(uint256 indexed _tokenId, uint256 _time);
    
    event UnlockCard(uint256 indexed _tokenId, uint256 _time);

    function cardNameAvailable(string calldata _name) external view returns (bool available_) {
        available_ = s.aavegotchiNamesUsed[LibBasketball.validateAndLowerName(_name)];
    }

    function currentRelease() external view returns (uint256 releaseId_, Release memory release_) {
        releaseId_ = s.currentReleaseId;
        release_ = s.releases[releaseId_];
    }

    struct RevenueSharesIO {
        address burnAddress;
        address daoAddress;
        address dfsnft;
    }

    function revenueShares() external view returns (RevenueSharesIO memory) {
        return RevenueSharesIO(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF, s.daoTreasury, s.dfsnft);
    }

    function cardPackTraits(uint256 _tokenId)
        external
        view
        returns (CardPackTraitsIO[PACK_CARDS_NUM] memory portalAavegotchiTraits_)
    {
        portalAavegotchiTraits_ = LibBasketball.cardPackTraits(_tokenId);
    }

    function daiAddress() external view returns (address contract_) {
        contract_ = s.daiContract;
    }

    function getNumericTraits(uint256 _tokenId) external view returns (int16[NUMERIC_TRAITS_NUM] memory numericTraits_) {
        numericTraits_ = LibBasketball.getNumericTraits(_tokenId);
    }

    function availableSkillPoints(uint256 _tokenId) public view returns (uint256) {
        uint256 level = LibBasketball.cardLevel(s.aavegotchis[_tokenId].experience);
        uint256 skillPoints = (level / 3);
        uint256 usedSkillPoints = s.aavegotchis[_tokenId].usedSkillPoints;
        require(skillPoints >= usedSkillPoints, "BasketballGameFacet: Used skill points is greater than skill points");
        return skillPoints - usedSkillPoints;
    }

    function cardLevel(uint256 _experience) external pure returns (uint256 level_) {
        level_ = LibBasketball.cardLevel(_experience);
    }

    function xpUntilNextLevel(uint256 _experience) external pure returns (uint256 requiredXp_) {
        requiredXp_ = LibBasketball.xpUntilNextLevel(_experience);
    }

    function rarityMultiplier(int16[NUMERIC_TRAITS_NUM] memory _numericTraits) external pure returns (uint256 multiplier_) {
        multiplier_ = LibBasketball.rarityMultiplier(_numericTraits);
    }

    //Calculates the base rarity score, including collateral modifier
    function baseRarityScore(int16[NUMERIC_TRAITS_NUM] memory _numericTraits) external pure returns (uint256 rarityScore_) {
        rarityScore_ = LibBasketball.baseRarityScore(_numericTraits);
    }

    //Only valid for claimed Aavegotchis
    function modifiedTraitsAndRarityScore(uint256 _tokenId)
        external
        view
        returns (int16[NUMERIC_TRAITS_NUM] memory numericTraits_, uint256 rarityScore_)
    {
        (numericTraits_, rarityScore_) = LibBasketball.modifiedTraitsAndRarityScore(_tokenId);
    }

    function morale(uint256 _tokenId) external view returns (uint256 score_) {
        score_ = LibBasketball.morale(_tokenId);
    }

    function claimCard(
        uint256 _tokenId,
        uint256 _option,
        uint256 _stakeAmount
    ) external onlyUnlocked(_tokenId) onlyCardOwner(_tokenId) {
        Card storage aavegotchi = s.aavegotchis[_tokenId];
        require(aavegotchi.status == LibBasketball.STATUS_OPEN_PORTAL, "BasketballGameFacet: Pack not open");
        require(_option < PACK_CARDS_NUM, "BasketballGameFacet: Only 5 card options available");
        uint256 randomNumber = s.tokenIdToRandomNumber[_tokenId];

        InternalCardPackTraitsIO memory option = LibBasketball.singleCardPackTraits(randomNumber, _option);
        aavegotchi.randomNumber = option.randomNumber;
        aavegotchi.numericTraits = option.numericTraits;
        aavegotchi.collateralType = option.collateralType;
        aavegotchi.minimumStake = option.minimumStake;
        aavegotchi.lastInteracted = uint40(block.timestamp - 12 hours);
        aavegotchi.interactionCount = 50;
        aavegotchi.claimTime = uint40(block.timestamp);

        require(_stakeAmount >= option.minimumStake, "BasketballGameFacet: _stakeAmount less than minimum stake");

        aavegotchi.status = LibBasketball.STATUS_AAVEGOTCHI;
        emit ClaimCard(_tokenId);

        address escrow = address(new CollateralEscrow(option.collateralType));
        aavegotchi.escrow = escrow;
        address owner = LibMeta.msgSender();
        LibERC20.transferFrom(option.collateralType, owner, escrow, _stakeAmount);
        LibERC721Marketplace.cancelERC721Listing(address(this), _tokenId, owner);
    }

    function setCardName(uint256 _tokenId, string calldata _name) external onlyUnlocked(_tokenId) onlyCardOwner(_tokenId) {
        require(s.aavegotchis[_tokenId].status == LibBasketball.STATUS_AAVEGOTCHI, "BasketballGameFacet: Must claim Card before setting name");
        string memory lowerName = LibBasketball.validateAndLowerName(_name);
        string memory existingName = s.aavegotchis[_tokenId].name;
        if (bytes(existingName).length > 0) {
            delete s.aavegotchiNamesUsed[LibBasketball.validateAndLowerName(existingName)];
        }
        require(!s.aavegotchiNamesUsed[lowerName], "BasketballGameFacet: Card name used already");
        s.aavegotchiNamesUsed[lowerName] = true;
        s.aavegotchis[_tokenId].name = _name;
        emit SetCardName(_tokenId, existingName, _name);
    }

    function interact(uint256[] calldata _tokenIds) external {
        address sender = LibMeta.msgSender();
        for (uint256 i; i < _tokenIds.length; i++) {
            uint256 tokenId = _tokenIds[i];
            address owner = s.aavegotchis[tokenId].owner;
            require(
                sender == owner || s.operators[owner][sender] || s.approved[tokenId] == sender,
                "BasketballGameFacet: Not owner of token or approved"
            );
            LibBasketball.interact(tokenId);
        }
    }

    function spendSkillPoints(uint256 _tokenId, int16[4] calldata _values) external onlyUnlocked(_tokenId) onlyCardOwner(_tokenId) {
        //To test (Dan): Prevent underflow (is this ok?), see require below
        uint256 totalUsed;
        for (uint256 index; index < _values.length; index++) {
            totalUsed += LibAppStorage.abs(_values[index]);

            s.aavegotchis[_tokenId].numericTraits[index] += _values[index];
        }
        // handles underflow
        require(availableSkillPoints(_tokenId) >= totalUsed, "BasketballGameFacet: Not enough skill points");
        //Increment used skill points
        s.aavegotchis[_tokenId].usedSkillPoints += totalUsed;
        emit SpendSkillPoints(_tokenId, _values);
    }
}
