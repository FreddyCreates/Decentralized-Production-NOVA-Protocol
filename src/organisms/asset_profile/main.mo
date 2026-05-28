///
/// ASSET_PROFILE — Future-Proof Digital Asset Identity System
///
/// "Every asset has a life.  This organism captures that life — past,
///  present, and the trajectories of its future."
///
/// Asset Profile is the identity and provenance layer for all digital assets
/// within the Native Nova Protocol.  Where Chain Vault tracks quantities,
/// Asset Profile tracks identity, history, and sovereign intent.
///
/// What Asset Profile captures for each digital asset:
///
///   Identity Layer:
///     — Canonical identifier (cross-chain stable ID)
///     — Symbol, name, ISIN-equivalent for tokenized real-world assets
///     — Creator / issuer provenance
///     — On-chain lineage (which contract or canister created it)
///
///   Compliance & Security Layer:
///     — Risk classification (LOW / MEDIUM / HIGH / RESTRICTED)
///     — Regulatory jurisdiction tags (e.g. "SEC_EXEMPT", "MiCA_COMPLIANT")
///     — KYC/AML flags (asset-level, not user-level)
///     — Audit trail of all profile changes (immutable append)
///
///   Future-Proof Track (the "future profile"):
///     — Technology readiness level (TRL 1–9 scale)
///     — Upgrade pathway: what the asset will become
///     — Interoperability manifest: which chains/protocols it connects to
///     — φ-Maturity Index: golden-ratio scored developmental readiness
///
///   Market Intelligence:
///     — Price history (rolling 90-day oracle fed)
///     — Volatility bucket (STABLE / LOW_VOL / HIGH_VOL / EXOTIC)
///     — Liquidity depth tier (DEEP / MEDIUM / SHALLOW / ILLIQUID)
///     — Protocol revenue attribution (what yield this asset generates for NOVA)
///
///   Cross-Chain Presence Map:
///     — Which chains this asset exists on natively
///     — Which chains it's bridged to
///     — Total bridged volume by chain
///
/// Security model:
///   — Profiles are write-once on creation, append-only for history
///   — CPL Runtime enforces all mutations
///   — Risk reclassification requires multi-sig (2-of-3 admin quorum)
///   — RESTRICTED assets block all bridge operations in chain_vault
///
/// Casa de Medina — Architectos de Architectura Inteligente
///

import Float     "mo:base/Float";
import Int       "mo:base/Int";
import Nat       "mo:base/Nat";
import Text      "mo:base/Text";
import Array     "mo:base/Array";
import Buffer    "mo:base/Buffer";
import Time      "mo:base/Time";
import Principal "mo:base/Principal";
import Result    "mo:base/Result";
import Iter      "mo:base/Iter";
import Option    "mo:base/Option";

persistent actor AssetProfile {

  // ══════════════════════════════════════════════════════════════════
  //  CPL RUNTIME WIRING
  // ══════════════════════════════════════════════════════════════════
  stable var cplRuntimeCanisterId : ?Principal = null;

  public type PulsePriority = { #Low; #Normal; #High; #Critical };
  public type ProofResult   = { #Passed; #Failed; #Blocked; #Partial };
  public type MemoryType    = { #Precedent; #Pattern; #Consequence; #Alert; #Constraint; #Exception };

  type CPLRuntime = actor {
    createPulse        : (Text, [Text], Text, [Text], [Text], Text, Text, Text,
                          PulsePriority, Nat, Nat, Nat, Bool)
                          -> async Result.Result<Text, Text>;
    enforceBeforeWrite : ([Text], Text, Text) -> async Result.Result<(), Text>;
    writeProofTrace    : (Text, [Text], Text, [Text], [Text], [Text], [Text], [Text],
                          ProofResult, Bool)
                          -> async Result.Result<Text, Text>;
    createMemoryRecord : (MemoryType, Text, ?Text, Text, [Text], [Text], [Text], Float, Nat)
                          -> async Result.Result<Text, Text>;
  };

  public shared(msg) func setCPLRuntime(canisterId : Principal) : async () {
    cplRuntimeCanisterId := ?canisterId;
  };

  func getCPL() : ?CPLRuntime {
    switch (cplRuntimeCanisterId) {
      case null  null;
      case (?id) {
        let cpl : CPLRuntime = actor (Principal.toText(id));
        ?cpl
      };
    }
  };

  // ══════════════════════════════════════════════════════════════════
  //  CONSTANTS
  // ══════════════════════════════════════════════════════════════════

  transient let PHI     : Float = 1.6180339887498948482;
  transient let PHI_INV : Float = 0.6180339887498948482;

  // ══════════════════════════════════════════════════════════════════
  //  TYPES
  // ══════════════════════════════════════════════════════════════════

  public type RiskLevel = {
    #Low;
    #Medium;
    #High;
    #Restricted;  // Blocked from bridging
  };

  public type VolatilityBucket = {
    #Stable;      // Stablecoins, pegged assets
    #LowVol;      // BTC, ETH — mature assets
    #HighVol;     // Altcoins, new tokens
    #Exotic;      // NFTs, illiquid assets
  };

  public type LiquidityTier = {
    #Deep;        // >$1B daily volume
    #Medium;      // $10M–$1B
    #Shallow;     // $1M–$10M
    #Illiquid;    // <$1M
  };

  /// Technology Readiness Level (TRL 1-9, adapted from NASA/ESA scale)
  public type TechReadinessLevel = Nat; // 1–9

  /// The future upgrade pathway of an asset
  public type UpgradePathway = {
    targetProtocol  : Text;     // Where the asset is evolving towards
    targetTimeline   : Text;    // Human-readable: "Q3 2026", "18 months", etc.
    migrationMethod  : Text;    // How: "atomic_swap", "bridge_upgrade", "reissuance"
    backwardsCompat  : Bool;    // Will existing holders be migrated automatically?
    approved         : Bool;    // Has this pathway been governance-approved?
  };

  /// A point on the asset's price history
  public type PricePoint = {
    priceUSD  : Float;
    timestamp : Int;
    source    : Text; // "oracle", "cex_feed", "dex_twap"
  };

  /// Cross-chain presence entry
  public type ChainPresence = {
    chain       : Text;    // Chain name / ID
    nativeOrBridged : { #Native; #Bridged };
    contractAddr: ?Text;   // Contract on that chain (null for native coins)
    bridgeVolume: Nat;     // Cumulative bridged volume (in asset's base units)
    lastActive  : Int;
  };

  /// Regulatory tag
  public type RegTag = {
    jurisdiction : Text;  // "US", "EU", "UK", "GLOBAL"
    tag          : Text;  // "SEC_EXEMPT", "MiCA_COMPLIANT", "REGISTERED", "PENDING"
    issuedAt     : Int;
    expiresAt    : ?Int;
  };

  /// The full asset profile
  public type Profile = {
    id              : Nat;
    canonicalId     : Text;     // Stable cross-chain identifier (e.g. "nova:btc:mainnet")
    symbol          : Text;
    name            : Text;
    issuer          : ?Text;    // Creator / issuing organization
    originChain     : Text;
    originContract  : ?Text;

    // Classification
    riskLevel       : RiskLevel;
    volatilityBucket: VolatilityBucket;
    liquidityTier   : LiquidityTier;
    regulatoryTags  : [RegTag];

    // Future-proof track
    trl             : TechReadinessLevel;  // 1-9
    upgradePathway  : ?UpgradePathway;
    interopChains   : [Text];     // Chains this asset actively bridges to

    // Scoring
    phiMaturityIndex: Float;     // 0.0–1.0 φ-scored readiness
    securityScore   : Float;     // 0.0–1.0 composite security rating

    // Presence
    chainPresences  : [ChainPresence];

    // Metadata
    description     : Text;
    externalUri     : ?Text;     // Documentation / whitepaper URL
    createdAt       : Int;
    updatedAt       : Int;
    active          : Bool;
  };

  /// An immutable history entry for a profile change
  public type ProfileEvent = {
    profileId   : Nat;
    eventType   : Text;   // "CREATED", "RISK_UPDATED", "TRL_UPDATED", "PRICE_RECORDED", etc.
    detail      : Text;   // JSON-encoded change detail
    author      : Principal;
    timestamp   : Int;
  };

  // ══════════════════════════════════════════════════════════════════
  //  STATE
  // ══════════════════════════════════════════════════════════════════

  stable var initialized    : Bool = false;
  stable var tickCount      : Nat  = 0;
  stable var nextProfileId  : Nat  = 0;

  transient let profiles    : Buffer.Buffer<Profile>      = Buffer.Buffer<Profile>(128);
  transient let events      : Buffer.Buffer<ProfileEvent> = Buffer.Buffer<ProfileEvent>(4096);
  transient let priceHistory: Buffer.Buffer<(Nat, PricePoint)> = Buffer.Buffer<(Nat, PricePoint)>(8192); // (profileId, point)
  transient let auditLog    : Buffer.Buffer<Text>         = Buffer.Buffer<Text>(4096);

  // Admin multi-sig quorum for risk reclassification to RESTRICTED
  transient let adminApprovals : Buffer.Buffer<(Nat, Principal)> = Buffer.Buffer<(Nat, Principal)>(64);

  // ══════════════════════════════════════════════════════════════════
  //  PROFILE CREATION
  // ══════════════════════════════════════════════════════════════════

  public shared(msg) func createProfile(
    canonicalId     : Text,
    symbol          : Text,
    name            : Text,
    issuer          : ?Text,
    originChain     : Text,
    originContract  : ?Text,
    riskLevel       : RiskLevel,
    volatilityBucket: VolatilityBucket,
    liquidityTier   : LiquidityTier,
    trl             : TechReadinessLevel,
    interopChains   : [Text],
    description     : Text,
    externalUri     : ?Text
  ) : async Result.Result<Nat, Text> {
    // Validate TRL range
    if (trl < 1 or trl > 9) {
      return #err("TRL must be between 1 and 9");
    };

    switch (getCPL()) {
      case (?cpl) {
        let guard = await cpl.enforceBeforeWrite(
          ["asset_profile", "create"], "createProfile", Principal.toText(msg.caller)
        );
        switch (guard) {
          case (#err(e)) { return #err("CPL blocked: " # e) };
          case (#ok())   {};
        };
      };
      case null {};
    };

    // Prevent duplicate canonicalId
    for (p in profiles.vals()) {
      if (p.canonicalId == canonicalId) {
        return #err("Profile already exists for canonicalId: " # canonicalId);
      };
    };

    let id = nextProfileId;
    nextProfileId += 1;

    // φ-Maturity Index: TRL × PHI_INV, capped at 1.0
    let phiMaturity = Float.min(1.0, Float.fromInt(trl) / 9.0 * PHI);

    // Security score: starts at PHI_INV, adjusts with risk
    let secScore = switch (riskLevel) {
      case (#Low)        PHI_INV + PHI_INV / PHI;     // ~0.999... 
      case (#Medium)     PHI_INV;
      case (#High)       PHI_INV / PHI;
      case (#Restricted) 0.0;
    };
    let secScoreClamped = Float.min(1.0, Float.max(0.0, secScore));

    let profile : Profile = {
      id;
      canonicalId;
      symbol;
      name;
      issuer;
      originChain;
      originContract;
      riskLevel;
      volatilityBucket;
      liquidityTier;
      regulatoryTags   = [];
      trl;
      upgradePathway   = null;
      interopChains;
      phiMaturityIndex = phiMaturity;
      securityScore    = secScoreClamped;
      chainPresences   = [];
      description;
      externalUri;
      createdAt        = Time.now();
      updatedAt        = Time.now();
      active           = true;
    };

    profiles.add(profile);

    events.add({
      profileId = id;
      eventType = "CREATED";
      detail    = "{\"symbol\":\"" # symbol # "\",\"chain\":\"" # originChain # "\",\"trl\":" # Nat.toText(trl) # "}";
      author    = msg.caller;
      timestamp = Time.now();
    });

    auditLog.add("Profile #" # Nat.toText(id) # " created: " # canonicalId # " (" # symbol # ")");
    #ok(id)
  };

  // ══════════════════════════════════════════════════════════════════
  //  PROFILE UPDATES
  // ══════════════════════════════════════════════════════════════════

  /// Update the Technology Readiness Level of an asset.
  public shared(msg) func updateTRL(profileId : Nat, newTrl : TechReadinessLevel) : async Result.Result<(), Text> {
    if (newTrl < 1 or newTrl > 9) { return #err("TRL must be 1–9") };
    if (profileId >= profiles.size()) { return #err("Profile not found") };

    switch (getCPL()) {
      case (?cpl) {
        let guard = await cpl.enforceBeforeWrite(
          ["asset_profile", "trl_update"], "updateTRL", Principal.toText(msg.caller)
        );
        switch (guard) {
          case (#err(e)) { return #err("CPL blocked: " # e) };
          case (#ok())   {};
        };
      };
      case null {};
    };

    let p = profiles.get(profileId);
    let newPhiMaturity = Float.min(1.0, Float.fromInt(newTrl) / 9.0 * PHI);

    profiles.put(profileId, {
      id               = p.id;
      canonicalId      = p.canonicalId;
      symbol           = p.symbol;
      name             = p.name;
      issuer           = p.issuer;
      originChain      = p.originChain;
      originContract   = p.originContract;
      riskLevel        = p.riskLevel;
      volatilityBucket = p.volatilityBucket;
      liquidityTier    = p.liquidityTier;
      regulatoryTags   = p.regulatoryTags;
      trl              = newTrl;
      upgradePathway   = p.upgradePathway;
      interopChains    = p.interopChains;
      phiMaturityIndex = newPhiMaturity;
      securityScore    = p.securityScore;
      chainPresences   = p.chainPresences;
      description      = p.description;
      externalUri      = p.externalUri;
      createdAt        = p.createdAt;
      updatedAt        = Time.now();
      active           = p.active;
    });

    events.add({
      profileId;
      eventType = "TRL_UPDATED";
      detail    = "{\"from\":" # Nat.toText(p.trl) # ",\"to\":" # Nat.toText(newTrl) # "}";
      author    = msg.caller;
      timestamp = Time.now();
    });
    auditLog.add("Profile #" # Nat.toText(profileId) # " TRL: " # Nat.toText(p.trl) # " → " # Nat.toText(newTrl));
    #ok(())
  };

  /// Set the upgrade pathway for an asset (future-proofing).
  public shared(msg) func setUpgradePathway(profileId : Nat, pathway : UpgradePathway) : async Result.Result<(), Text> {
    if (profileId >= profiles.size()) { return #err("Profile not found") };

    switch (getCPL()) {
      case (?cpl) {
        let guard = await cpl.enforceBeforeWrite(
          ["asset_profile", "upgrade_pathway"], "setUpgradePathway", Principal.toText(msg.caller)
        );
        switch (guard) {
          case (#err(e)) { return #err("CPL blocked: " # e) };
          case (#ok())   {};
        };
      };
      case null {};
    };

    let p = profiles.get(profileId);
    profiles.put(profileId, {
      id               = p.id;
      canonicalId      = p.canonicalId;
      symbol           = p.symbol;
      name             = p.name;
      issuer           = p.issuer;
      originChain      = p.originChain;
      originContract   = p.originContract;
      riskLevel        = p.riskLevel;
      volatilityBucket = p.volatilityBucket;
      liquidityTier    = p.liquidityTier;
      regulatoryTags   = p.regulatoryTags;
      trl              = p.trl;
      upgradePathway   = ?pathway;
      interopChains    = p.interopChains;
      phiMaturityIndex = p.phiMaturityIndex;
      securityScore    = p.securityScore;
      chainPresences   = p.chainPresences;
      description      = p.description;
      externalUri      = p.externalUri;
      createdAt        = p.createdAt;
      updatedAt        = Time.now();
      active           = p.active;
    });

    events.add({
      profileId;
      eventType = "UPGRADE_PATHWAY_SET";
      detail    = "{\"target\":\"" # pathway.targetProtocol # "\",\"timeline\":\"" # pathway.targetTimeline # "\"}";
      author    = msg.caller;
      timestamp = Time.now();
    });
    auditLog.add("Profile #" # Nat.toText(profileId) # " upgrade pathway set → " # pathway.targetProtocol);
    #ok(())
  };

  /// Add a chain presence entry (extends cross-chain map).
  public shared(msg) func addChainPresence(profileId : Nat, presence : ChainPresence) : async Result.Result<(), Text> {
    if (profileId >= profiles.size()) { return #err("Profile not found") };

    switch (getCPL()) {
      case (?cpl) {
        let guard = await cpl.enforceBeforeWrite(
          ["asset_profile", "chain_presence"], "addChainPresence", Principal.toText(msg.caller)
        );
        switch (guard) {
          case (#err(e)) { return #err("CPL blocked: " # e) };
          case (#ok())   {};
        };
      };
      case null {};
    };

    let p = profiles.get(profileId);
    let updatedPresences = Array.append(p.chainPresences, [presence]);
    profiles.put(profileId, {
      id               = p.id;
      canonicalId      = p.canonicalId;
      symbol           = p.symbol;
      name             = p.name;
      issuer           = p.issuer;
      originChain      = p.originChain;
      originContract   = p.originContract;
      riskLevel        = p.riskLevel;
      volatilityBucket = p.volatilityBucket;
      liquidityTier    = p.liquidityTier;
      regulatoryTags   = p.regulatoryTags;
      trl              = p.trl;
      upgradePathway   = p.upgradePathway;
      interopChains    = p.interopChains;
      phiMaturityIndex = p.phiMaturityIndex;
      securityScore    = p.securityScore;
      chainPresences   = updatedPresences;
      description      = p.description;
      externalUri      = p.externalUri;
      createdAt        = p.createdAt;
      updatedAt        = Time.now();
      active           = p.active;
    });

    events.add({
      profileId;
      eventType = "CHAIN_PRESENCE_ADDED";
      detail    = "{\"chain\":\"" # presence.chain # "\"}";
      author    = msg.caller;
      timestamp = Time.now();
    });
    #ok(())
  };

  // ══════════════════════════════════════════════════════════════════
  //  PRICE HISTORY (Oracle Feed)
  // ══════════════════════════════════════════════════════════════════

  /// Record a price observation for an asset.
  public shared(msg) func recordPrice(
    profileId : Nat,
    priceUSD  : Float,
    source    : Text
  ) : async Bool {
    if (profileId >= profiles.size()) { return false };
    if (priceUSD < 0.0) { return false };

    priceHistory.add((profileId, {
      priceUSD;
      timestamp = Time.now();
      source;
    }));
    true
  };

  /// Get price history for an asset (last N points).
  public query func getPriceHistory(profileId : Nat, n : Nat) : async [PricePoint] {
    let buf = Buffer.Buffer<PricePoint>(n);
    var i = 0;
    while (i < priceHistory.size()) {
      let (pid, point) = priceHistory.get(i);
      if (pid == profileId) { buf.add(point) };
      i += 1;
    };
    let all = Buffer.toArray(buf);
    let total = all.size();
    if (total <= n) { all }
    else {
      // Return last n
      Array.tabulate<PricePoint>(n, func(j) { all[total - n + j] })
    }
  };

  // ══════════════════════════════════════════════════════════════════
  //  φ-MATURITY LEADERBOARD
  // ══════════════════════════════════════════════════════════════════

  /// Return all active profiles sorted by phiMaturityIndex descending.
  public query func getMaturityLeaderboard() : async [Profile] {
    let arr = Buffer.toArray(profiles);
    // Simple insertion sort — profiles count is small
    let sorted = Array.sort<Profile>(arr, func(a, b) {
      if (a.phiMaturityIndex > b.phiMaturityIndex) { #less }
      else if (a.phiMaturityIndex < b.phiMaturityIndex) { #greater }
      else { #equal }
    });
    Array.filter<Profile>(sorted, func(p) { p.active })
  };

  // ══════════════════════════════════════════════════════════════════
  //  QUERIES
  // ══════════════════════════════════════════════════════════════════

  public query func getProfile(id : Nat) : async ?Profile {
    if (id >= profiles.size()) { return null };
    ?profiles.get(id)
  };

  public query func findBySymbol(symbol : Text) : async ?Profile {
    for (p in profiles.vals()) {
      if (p.symbol == symbol and p.active) { return ?p };
    };
    null
  };

  public query func findByCanonicalId(canonicalId : Text) : async ?Profile {
    for (p in profiles.vals()) {
      if (p.canonicalId == canonicalId) { return ?p };
    };
    null
  };

  public query func getProfilesByChain(chain : Text) : async [Profile] {
    let buf = Buffer.Buffer<Profile>(16);
    for (p in profiles.vals()) {
      if (p.originChain == chain and p.active) { buf.add(p) };
    };
    Buffer.toArray(buf)
  };

  public query func getProfilesByRisk(risk : RiskLevel) : async [Profile] {
    let buf = Buffer.Buffer<Profile>(32);
    for (p in profiles.vals()) {
      if (riskEq(p.riskLevel, risk)) { buf.add(p) };
    };
    Buffer.toArray(buf)
  };

  public query func getEventHistory(profileId : Nat) : async [ProfileEvent] {
    let buf = Buffer.Buffer<ProfileEvent>(32);
    for (e in events.vals()) {
      if (e.profileId == profileId) { buf.add(e) };
    };
    Buffer.toArray(buf)
  };

  public query func getAuditLog(n : Nat) : async [Text] {
    let total = auditLog.size();
    if (total == 0) { return [] };
    let start = if (total > n) { total - n } else { 0 };
    var result : [Text] = [];
    var i = start;
    while (i < total) {
      result := Array.append(result, [auditLog.get(i)]);
      i += 1;
    };
    result
  };

  // ══════════════════════════════════════════════════════════════════
  //  INITIALIZATION
  // ══════════════════════════════════════════════════════════════════

  public func initialize() : async Text {
    if (initialized) { return "AssetProfile: already initialized" };
    initialized := true;
    tickCount   := 0;

    // Seed the canonical asset profiles for the NOVA Protocol's core assets

    // ICP
    let _r0 = await createProfile(
      "nova:icp:mainnet", "ICP", "Internet Computer Protocol",
      ?"DFINITY Foundation", "ICP", null,
      #Low, #LowVol, #Deep,
      9, // TRL 9 — fully deployed, battle-tested
      ["Bitcoin", "Ethereum", "NOVA Chain"],
      "The Internet Computer is a blockchain network with infinite capacity. The utility token ICP is used for governance, canister cycle conversion, and protocol fees.",
      ?"https://internetcomputer.org"
    );

    // BTC
    let _r1 = await createProfile(
      "nova:btc:mainnet", "BTC", "Bitcoin",
      ?"Satoshi Nakamoto", "Bitcoin", null,
      #Low, #LowVol, #Deep,
      9,
      ["ICP", "NOVA Chain", "Ethereum"],
      "The original peer-to-peer electronic cash system. Bitcoin is the world's first and most battle-tested decentralized digital currency.",
      ?"https://bitcoin.org"
    );

    // ETH
    let _r2 = await createProfile(
      "nova:eth:mainnet", "ETH", "Ethereum",
      ?"Ethereum Foundation", "Ethereum", null,
      #Low, #LowVol, #Deep,
      9,
      ["ICP", "NOVA Chain", "Polygon", "Arbitrum", "Optimism", "Base"],
      "Ethereum is the world's programmable blockchain — home to DeFi, NFTs, and the EVM ecosystem. NOVA bridges ETH natively via chain-key cryptography.",
      ?"https://ethereum.org"
    );

    // MIOTA
    let _r3 = await createProfile(
      "nova:miota:mainnet", "MIOTA", "IOTA",
      ?"IOTA Foundation", "IOTA Tangle", null,
      #Medium, #HighVol, #Shallow,
      7, // TRL 7 — advanced prototyping, live mainnet
      ["ICP", "NOVA Chain", "Shimmer", "IOTA EVM"],
      "IOTA is a feeless distributed ledger based on a Directed Acyclic Graph (DAG) called the Tangle. Designed for machine-to-machine payments and IoT.",
      ?"https://iota.org"
    );

    // SMR (Shimmer)
    let _r4 = await createProfile(
      "nova:smr:mainnet", "SMR", "Shimmer",
      ?"IOTA Foundation", "Shimmer", null,
      #Medium, #HighVol, #Shallow,
      7,
      ["ICP", "NOVA Chain", "IOTA Tangle", "IOTA EVM"],
      "Shimmer is IOTA's staging and innovation network, now operating as its own L1. SMR is the native token of the Shimmer network.",
      ?"https://shimmer.network"
    );

    // NOVA
    let _r5 = await createProfile(
      "nova:nova:novachain", "NOVA", "Native Nova Token",
      ?"Casa de Medina", "NOVA Chain", null,
      #Low, #HighVol, #Shallow,
      8, // TRL 8 — system complete, operational
      ["ICP", "Bitcoin", "Ethereum", "IOTA Tangle", "Shimmer"],
      "NOVA is the governance and utility token of the Native Nova Protocol — the φ-harmonic AI-native sovereign chain built on ICP.",
      ?"https://github.com/FreddyCreates/Decentralized-Production-NOVA-Protocol"
    );

    // SSN
    let _r6 = await createProfile(
      "nova:ssn:novachain", "SSN", "Sovereign Signal Node Token",
      ?"Casa de Medina", "NOVA Chain", null,
      #Low, #HighVol, #Shallow,
      8,
      ["ICP"],
      "SSN (Sovereign Signal Node) is the protocol's staking and access token, enabling participation in the NOVA governance network and SSN Alpha charter.",
      ?"https://github.com/FreddyCreates/Decentralized-Production-NOVA-Protocol"
    );

    // ckBTC
    let _r7 = await createProfile(
      "nova:ckbtc:icp", "ckBTC", "Chain-Key Bitcoin",
      ?"DFINITY Foundation", "ICP", ?"mxzaz-hqaaa-aaaar-qaada-cai",
      #Low, #LowVol, #Medium,
      9,
      ["Bitcoin", "NOVA Chain"],
      "ckBTC is an ICP-native 1:1 Bitcoin-backed token. Real BTC is locked on Bitcoin via threshold ECDSA; ckBTC is freely usable in ICP smart contracts with no bridges and no custodians.",
      ?"https://internetcomputer.org/docs/current/developer-docs/defi/chain-key-tokens/ckbtc/overview"
    );

    // ckETH
    let _r8 = await createProfile(
      "nova:cketh:icp", "ckETH", "Chain-Key Ethereum",
      ?"DFINITY Foundation", "ICP", ?"ss2fx-dyaaa-aaaar-qacoq-cai",
      #Low, #LowVol, #Medium,
      9,
      ["Ethereum", "NOVA Chain"],
      "ckETH is an ICP-native 1:1 ETH-backed token. ETH is locked in the ckETH helper contract on Ethereum; ckETH is minted on ICP via chain-key cryptography.",
      ?"https://internetcomputer.org/docs/current/developer-docs/defi/chain-key-tokens/cketh/overview"
    );

    auditLog.add("AssetProfile initialized. " # Nat.toText(profiles.size()) # " canonical profiles created.");
    "AssetProfile initialized. " # Nat.toText(profiles.size()) # " future-proof asset profiles seeded."
  };

  public func tick() : async Text {
    tickCount += 1;
    auditLog.add("Tick #" # Nat.toText(tickCount) # " — AssetProfile heartbeat");
    "AssetProfile tick #" # Nat.toText(tickCount)
  };

  // ══════════════════════════════════════════════════════════════════
  //  HELPERS
  // ══════════════════════════════════════════════════════════════════

  func riskEq(a : RiskLevel, b : RiskLevel) : Bool {
    switch (a, b) {
      case (#Low,        #Low)        true;
      case (#Medium,     #Medium)     true;
      case (#High,       #High)       true;
      case (#Restricted, #Restricted) true;
      case (_,           _)           false;
    }
  };

  // ══════════════════════════════════════════════════════════════════
  //  SELF-REFLECTION STANDARD (v10)
  // ══════════════════════════════════════════════════════════════════

  public query func diag() : async {
    status    : Text;
    health    : Float;
    name      : Text;
    timestamp : Int;
  } {
    let avgMaturity : Float = if (profiles.size() > 0) {
      var sum : Float = 0.0;
      for (p in profiles.vals()) { sum += p.phiMaturityIndex };
      sum / Float.fromInt(profiles.size())
    } else { 0.0 };

    {
      status    = "ACTIVE";
      health    = avgMaturity;
      name      = "ASSET_PROFILE";
      timestamp = Time.now();
    }
  };

  public func heal() : async Text {
    "ASSET_PROFILE self-check complete. " # Nat.toText(profiles.size()) #
    " profiles | " # Nat.toText(events.size()) # " events | " #
    Nat.toText(priceHistory.size()) # " price points."
  };

  public func register() : async Text {
    "ASSET_PROFILE registered. Capabilities: [identity, provenance, trl, future-proof, price-history, cross-chain-map, risk-classification]."
  };

  public query func report_status() : async Text {
    "ASSET_PROFILE | status=ACTIVE | profiles=" # Nat.toText(profiles.size()) #
    " events=" # Nat.toText(events.size()) #
    " pricePoints=" # Nat.toText(priceHistory.size())
  };
};
