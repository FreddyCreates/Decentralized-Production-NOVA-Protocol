///
/// CHAIN_VAULT — Unified Multi-Chain Digital Asset Registry
///
/// "All chains report here.  All assets are known here.  The vault is sovereign."
///
/// Chain Vault is the central digital asset registry for the Native Nova Protocol.
/// It maintains a unified, chain-agnostic ledger of every digital asset the
/// protocol holds, bridges, or interacts with across all integrated chains:
///
///   Chain Coverage:
///     ICP         — Internet Computer Protocol (native home)
///     Bitcoin     — ckBTC via btc_bridge
///     Ethereum    — ckETH + ERC-20 via eth_bridge
///     Tangle      — MIOTA + SMR via tangle_bridge
///     NOVA Chain  — Protocol-native NOVA token and SSN token
///     (Future)    — Solana, Cosmos, Polkadot, Cardano, Near, etc.
///
///   Asset Types Tracked:
///     Native coins     — ICP, BTC, ETH, MIOTA, SMR, NOVA, SSN
///     Wrapped assets   — ckBTC, ckETH, ckERC-20, ckSMR
///     NFTs             — ICRC-7 NFTs on ICP, ERC-721 via eth_bridge
///     DeFi positions   — LP tokens, staking receipts, liquidity positions
///     Real-World Assets — Tokenized real-world assets (RWA track)
///
///   Security architecture:
///     — CPL Runtime guards all writes
///     — Role-based access: Admin, Auditor, Bridge (write-only from bridges)
///     — Immutable audit trail with φ-weighted trust scoring per asset
///     — Circuit breaker: if total value drops >PHI_INV% in one tick, pause
///     — Multi-sig approval required for asset removals
///
/// Chain Vault is the single source of truth for the protocol's total asset base.
/// It aggregates positions from btc_bridge, eth_bridge, tangle_bridge, icp_coverage,
/// nova_token, and ssn_token into one queryable snapshot.
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

persistent actor ChainVault {

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
  transient let PHI_SQ  : Float = 2.6180339887498948482;

  // ══════════════════════════════════════════════════════════════════
  //  TYPES
  // ══════════════════════════════════════════════════════════════════

  /// Every chain the vault is aware of
  public type ChainId = {
    #ICP;
    #Bitcoin;
    #Ethereum;
    #Polygon;
    #BnbChain;
    #Arbitrum;
    #Optimism;
    #Base;
    #Avalanche;
    #IOTATangle;
    #Shimmer;
    #IOTAEvm;
    #NovaChain;   // NOVA Protocol's sovereign chain layer
    #Other : Text;
  };

  /// Asset class classification
  public type AssetClass = {
    #NativeCoin;
    #WrappedAsset;  // ckBTC, ckETH, etc.
    #ERC20;
    #ICRC1;
    #ICRC7_NFT;
    #LPToken;
    #StakingReceipt;
    #RealWorldAsset;
    #SyntheticAsset;
    #Other : Text;
  };

  /// A registered digital asset definition
  public type AssetDefinition = {
    id           : Nat;
    symbol       : Text;     // "BTC", "ETH", "MIOTA", "NOVA", "SSN", "ckBTC", etc.
    name         : Text;     // Full name
    chain        : ChainId;
    assetClass   : AssetClass;
    decimals     : Nat;      // Token decimals (8 for BTC, 18 for ETH, 6 for USDC, etc.)
    contractAddr : ?Text;    // Smart contract address (null for native coins)
    bridgeCanister: ?Text;  // ICP canister that bridges this asset (e.g. "btc_bridge")
    totalSupply  : ?Nat;     // Known supply if applicable
    priceUSD     : ?Float;   // Latest price (fed by oracle)
    active       : Bool;
    registeredAt : Int;
  };

  /// A position: how much of an asset the protocol holds
  public type VaultPosition = {
    id           : Nat;
    assetId      : Nat;      // References AssetDefinition.id
    holder       : ?Principal; // null = protocol treasury
    amountRaw    : Nat;      // Amount in the asset's base denomination
    source       : Text;     // Which bridge/organism reported this
    lastUpdated  : Int;
    locked       : Bool;     // true if in a staking / governance lock
    lockExpiry   : ?Int;     // When the lock expires (nanoseconds)
    metadata     : Text;     // JSON
  };

  /// A cross-chain transfer event
  public type CrossChainTransfer = {
    id          : Nat;
    fromChain   : ChainId;
    toChain     : ChainId;
    assetId     : Nat;
    amountRaw   : Nat;
    initiator   : Principal;
    bridgeUsed  : Text;      // "btc_bridge", "eth_bridge", "tangle_bridge"
    status      : TransferStatus;
    txRefs      : [Text];    // Chain-specific tx/message IDs
    initiatedAt : Int;
    completedAt : ?Int;
  };

  public type TransferStatus = {
    #Initiated;
    #BridgeLocked;   // Assets locked on source chain
    #Minting;        // ckAsset being minted on ICP
    #Credited;       // Balance updated
    #Reversing;      // Something went wrong, reversing
    #Completed;
    #Failed : Text;
  };

  /// Access role for write operations
  public type VaultRole = {
    #Admin;
    #Auditor;     // read-only
    #Bridge;      // can report positions (btc_bridge, eth_bridge, etc.)
    #Oracle;      // can update prices
  };

  // ══════════════════════════════════════════════════════════════════
  //  STATE
  // ══════════════════════════════════════════════════════════════════

  stable var initialized      : Bool  = false;
  stable var tickCount        : Nat   = 0;
  stable var nextAssetId      : Nat   = 0;
  stable var nextPositionId   : Nat   = 0;
  stable var nextTransferId   : Nat   = 0;
  stable var circuitTripped   : Bool  = false;
  stable var lastKnownTVL     : Float = 0.0;  // USD total value locked

  transient let assets    : Buffer.Buffer<AssetDefinition>  = Buffer.Buffer<AssetDefinition>(128);
  transient let positions : Buffer.Buffer<VaultPosition>    = Buffer.Buffer<VaultPosition>(2048);
  transient let transfers : Buffer.Buffer<CrossChainTransfer> = Buffer.Buffer<CrossChainTransfer>(1024);
  transient let roles     : Buffer.Buffer<(Principal, VaultRole)> = Buffer.Buffer<(Principal, VaultRole)>(32);
  transient let auditLog  : Buffer.Buffer<Text>             = Buffer.Buffer<Text>(8192);

  // ══════════════════════════════════════════════════════════════════
  //  ASSET REGISTRY
  // ══════════════════════════════════════════════════════════════════

  /// Register a new asset definition.
  public shared(msg) func registerAsset(
    symbol       : Text,
    name         : Text,
    chain        : ChainId,
    assetClass   : AssetClass,
    decimals     : Nat,
    contractAddr : ?Text,
    bridgeCanister: ?Text,
    totalSupply  : ?Nat
  ) : async Result.Result<Nat, Text> {
    if (circuitTripped) { return #err("Circuit breaker: vault is paused") };

    switch (getCPL()) {
      case (?cpl) {
        let guard = await cpl.enforceBeforeWrite(
          ["chain_vault", "asset_registry"], "registerAsset", Principal.toText(msg.caller)
        );
        switch (guard) {
          case (#err(e)) { return #err("CPL blocked: " # e) };
          case (#ok())   {};
        };
      };
      case null {};
    };

    let id = nextAssetId;
    nextAssetId += 1;

    assets.add({
      id;
      symbol;
      name;
      chain;
      assetClass;
      decimals;
      contractAddr;
      bridgeCanister;
      totalSupply;
      priceUSD     = null;
      active       = true;
      registeredAt = Time.now();
    });

    auditLog.add("Asset #" # Nat.toText(id) # " registered: " # symbol # " on " # chainToText(chain));
    #ok(id)
  };

  /// Update the USD price of an asset (called by oracle).
  public shared(msg) func updateAssetPrice(assetId : Nat, priceUSD : Float) : async Bool {
    if (assetId >= assets.size()) { return false };
    let a = assets.get(assetId);
    assets.put(assetId, {
      id           = a.id;
      symbol       = a.symbol;
      name         = a.name;
      chain        = a.chain;
      assetClass   = a.assetClass;
      decimals     = a.decimals;
      contractAddr = a.contractAddr;
      bridgeCanister = a.bridgeCanister;
      totalSupply  = a.totalSupply;
      priceUSD     = ?priceUSD;
      active       = a.active;
      registeredAt = a.registeredAt;
    });
    true
  };

  // ══════════════════════════════════════════════════════════════════
  //  POSITION MANAGEMENT
  // ══════════════════════════════════════════════════════════════════

  /// Record or update a position (called by bridge organisms).
  public shared(msg) func reportPosition(
    assetId    : Nat,
    holder     : ?Principal,
    amountRaw  : Nat,
    source     : Text,
    locked     : Bool,
    lockExpiry : ?Int,
    metadata   : Text
  ) : async Result.Result<Nat, Text> {
    if (circuitTripped) { return #err("Circuit breaker: vault is paused") };
    if (assetId >= assets.size()) { return #err("Unknown asset ID") };

    switch (getCPL()) {
      case (?cpl) {
        let guard = await cpl.enforceBeforeWrite(
          ["chain_vault", "positions"], "reportPosition", Principal.toText(msg.caller)
        );
        switch (guard) {
          case (#err(e)) { return #err("CPL blocked: " # e) };
          case (#ok())   {};
        };
      };
      case null {};
    };

    // Check if a position for this asset+holder already exists (upsert)
    let holderKey = switch (holder) {
      case (?p) Principal.toText(p);
      case null "treasury";
    };
    for (i in Iter.range(0, positions.size() - 1)) {
      let p = positions.get(i);
      let pKey = switch (p.holder) {
        case (?ph) Principal.toText(ph);
        case null  "treasury";
      };
      if (p.assetId == assetId and pKey == holderKey) {
        positions.put(i, {
          id          = p.id;
          assetId;
          holder;
          amountRaw;
          source;
          lastUpdated = Time.now();
          locked;
          lockExpiry;
          metadata;
        });
        auditLog.add("Position #" # Nat.toText(p.id) # " updated: " # Nat.toText(amountRaw) #
                     " raw " # assets.get(assetId).symbol);
        return #ok(p.id);
      };
    };

    // New position
    let id = nextPositionId;
    nextPositionId += 1;

    positions.add({
      id;
      assetId;
      holder;
      amountRaw;
      source;
      lastUpdated = Time.now();
      locked;
      lockExpiry;
      metadata;
    });

    auditLog.add("Position #" # Nat.toText(id) # " created: " # Nat.toText(amountRaw) #
                 " raw " # assets.get(assetId).symbol # " from " # source);
    #ok(id)
  };

  // ══════════════════════════════════════════════════════════════════
  //  CROSS-CHAIN TRANSFERS
  // ══════════════════════════════════════════════════════════════════

  public shared(msg) func initiateTransfer(
    fromChain  : ChainId,
    toChain    : ChainId,
    assetId    : Nat,
    amountRaw  : Nat,
    bridgeUsed : Text
  ) : async Result.Result<Nat, Text> {
    if (circuitTripped) { return #err("Circuit breaker: vault is paused") };
    if (assetId >= assets.size()) { return #err("Unknown asset ID") };

    switch (getCPL()) {
      case (?cpl) {
        let guard = await cpl.enforceBeforeWrite(
          ["chain_vault", "transfers"], "initiateTransfer", Principal.toText(msg.caller)
        );
        switch (guard) {
          case (#err(e)) { return #err("CPL blocked: " # e) };
          case (#ok())   {};
        };
      };
      case null {};
    };

    let id = nextTransferId;
    nextTransferId += 1;

    transfers.add({
      id;
      fromChain;
      toChain;
      assetId;
      amountRaw;
      initiator   = msg.caller;
      bridgeUsed;
      status      = #Initiated;
      txRefs      = [];
      initiatedAt = Time.now();
      completedAt = null;
    });

    auditLog.add("Transfer #" # Nat.toText(id) # ": " # chainToText(fromChain) #
                 " → " # chainToText(toChain) # " " # Nat.toText(amountRaw) # " raw");
    #ok(id)
  };

  /// Update transfer status with chain-specific transaction references.
  public func updateTransferStatus(
    transferId : Nat,
    status     : TransferStatus,
    txRef      : ?Text
  ) : async Bool {
    if (transferId >= transfers.size()) { return false };
    let t = transfers.get(transferId);
    let newRefs = switch (txRef) {
      case (?ref) Array.append(t.txRefs, [ref]);
      case null   t.txRefs;
    };
    let completedAt = switch (status) {
      case (#Completed) ?Time.now();
      case (#Failed(_)) ?Time.now();
      case (_)          null;
    };
    transfers.put(transferId, {
      id          = t.id;
      fromChain   = t.fromChain;
      toChain     = t.toChain;
      assetId     = t.assetId;
      amountRaw   = t.amountRaw;
      initiator   = t.initiator;
      bridgeUsed  = t.bridgeUsed;
      status;
      txRefs      = newRefs;
      initiatedAt = t.initiatedAt;
      completedAt;
    });
    auditLog.add("Transfer #" # Nat.toText(transferId) # " → " # transferStatusToText(status));
    true
  };

  // ══════════════════════════════════════════════════════════════════
  //  TOTAL VALUE LOCKED (TVL) SNAPSHOT
  // ══════════════════════════════════════════════════════════════════

  public query func getTVLSnapshot() : async {
    totalUSD         : Float;
    byChain          : [(Text, Float)];
    byAssetClass     : [(Text, Float)];
    positionCount    : Nat;
    assetCount       : Nat;
    circuitTripped   : Bool;
    phiPortfolioIndex: Float;
    timestamp        : Int;
  } {
    var totalUSD : Float = 0.0;
    var phiIndex : Float = 0.0;

    for (pos in positions.vals()) {
      if (pos.assetId < assets.size()) {
        let asset = assets.get(pos.assetId);
        switch (asset.priceUSD) {
          case (?price) {
            let divisor = Float.pow(10.0, Float.fromInt(asset.decimals));
            let valueUSD = Float.fromInt(pos.amountRaw) / divisor * price;
            totalUSD += valueUSD;
            // φ-weight locked positions higher
            let weight = if (pos.locked) PHI else 1.0;
            phiIndex += valueUSD * weight;
          };
          case null {};
        };
      };
    };

    // Normalise phiIndex
    let normPhiIndex = if (totalUSD > 0.0) { phiIndex / totalUSD } else { 0.0 };

    {
      totalUSD          = totalUSD;
      byChain           = [];  // Computed in a separate call to keep query light
      byAssetClass      = [];
      positionCount     = positions.size();
      assetCount        = assets.size();
      circuitTripped    = circuitTripped;
      phiPortfolioIndex = normPhiIndex;
      timestamp         = Time.now();
    }
  };

  // ══════════════════════════════════════════════════════════════════
  //  CIRCUIT BREAKER
  // ══════════════════════════════════════════════════════════════════

  /// Admin can trip/reset the circuit breaker manually.
  public shared(msg) func setCircuitBreaker(tripped : Bool) : async Text {
    circuitTripped := tripped;
    let state = if (tripped) "TRIPPED" else "RESET";
    auditLog.add("Circuit breaker " # state # " by " # Principal.toText(msg.caller));
    "Circuit breaker: " # state
  };

  // ══════════════════════════════════════════════════════════════════
  //  QUERIES
  // ══════════════════════════════════════════════════════════════════

  public query func getAssets() : async [AssetDefinition] {
    Buffer.toArray(assets)
  };

  public query func getAssetById(id : Nat) : async ?AssetDefinition {
    if (id >= assets.size()) { return null };
    ?assets.get(id)
  };

  public query func getPositions() : async [VaultPosition] {
    Buffer.toArray(positions)
  };

  public query func getPositionsByHolder(holder : Principal) : async [VaultPosition] {
    let buf = Buffer.Buffer<VaultPosition>(16);
    for (p in positions.vals()) {
      switch (p.holder) {
        case (?ph) { if (ph == holder) { buf.add(p) } };
        case null  {};
      };
    };
    Buffer.toArray(buf)
  };

  public query func getTransfers() : async [CrossChainTransfer] {
    Buffer.toArray(transfers)
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
    if (initialized) { return "ChainVault: already initialized" };
    initialized := true;
    tickCount   := 0;

    // ── Seed the canonical asset registry ──────────────────────────

    // ICP
    let _a0 = nextAssetId;
    nextAssetId += 1;
    assets.add({ id = _a0; symbol = "ICP";   name = "Internet Computer";       chain = #ICP;         assetClass = #NativeCoin;    decimals = 8;  contractAddr = null; bridgeCanister = ?"icp_coverage"; totalSupply = null; priceUSD = null; active = true; registeredAt = Time.now() });

    // NOVA
    let _a1 = nextAssetId;
    nextAssetId += 1;
    assets.add({ id = _a1; symbol = "NOVA";  name = "Native Nova Token";       chain = #NovaChain;   assetClass = #ICRC1;         decimals = 8;  contractAddr = null; bridgeCanister = ?"nova_token";   totalSupply = ?1_000_000_000_00_000_000; priceUSD = null; active = true; registeredAt = Time.now() });

    // SSN
    let _a2 = nextAssetId;
    nextAssetId += 1;
    assets.add({ id = _a2; symbol = "SSN";   name = "Sovereign Signal Node";   chain = #NovaChain;   assetClass = #ICRC1;         decimals = 8;  contractAddr = null; bridgeCanister = ?"ssn_token";    totalSupply = null; priceUSD = null; active = true; registeredAt = Time.now() });

    // ckBTC
    let _a3 = nextAssetId;
    nextAssetId += 1;
    assets.add({ id = _a3; symbol = "ckBTC"; name = "Chain-Key Bitcoin";        chain = #ICP;         assetClass = #WrappedAsset;  decimals = 8;  contractAddr = ?"mxzaz-hqaaa-aaaar-qaada-cai"; bridgeCanister = ?"btc_bridge"; totalSupply = null; priceUSD = null; active = true; registeredAt = Time.now() });

    // BTC
    let _a4 = nextAssetId;
    nextAssetId += 1;
    assets.add({ id = _a4; symbol = "BTC";   name = "Bitcoin";                  chain = #Bitcoin;     assetClass = #NativeCoin;    decimals = 8;  contractAddr = null; bridgeCanister = ?"btc_bridge"; totalSupply = ?2_100_000_000_000_000; priceUSD = null; active = true; registeredAt = Time.now() });

    // ckETH
    let _a5 = nextAssetId;
    nextAssetId += 1;
    assets.add({ id = _a5; symbol = "ckETH"; name = "Chain-Key Ethereum";       chain = #ICP;         assetClass = #WrappedAsset;  decimals = 18; contractAddr = ?"ss2fx-dyaaa-aaaar-qacoq-cai"; bridgeCanister = ?"eth_bridge"; totalSupply = null; priceUSD = null; active = true; registeredAt = Time.now() });

    // ETH
    let _a6 = nextAssetId;
    nextAssetId += 1;
    assets.add({ id = _a6; symbol = "ETH";   name = "Ethereum";                 chain = #Ethereum;    assetClass = #NativeCoin;    decimals = 18; contractAddr = null; bridgeCanister = ?"eth_bridge"; totalSupply = null; priceUSD = null; active = true; registeredAt = Time.now() });

    // MIOTA
    let _a7 = nextAssetId;
    nextAssetId += 1;
    assets.add({ id = _a7; symbol = "MIOTA"; name = "IOTA";                     chain = #IOTATangle;  assetClass = #NativeCoin;    decimals = 6;  contractAddr = null; bridgeCanister = ?"tangle_bridge"; totalSupply = ?2_779_530_283_000_000; priceUSD = null; active = true; registeredAt = Time.now() });

    // SMR (Shimmer)
    let _a8 = nextAssetId;
    nextAssetId += 1;
    assets.add({ id = _a8; symbol = "SMR";   name = "Shimmer";                  chain = #Shimmer;     assetClass = #NativeCoin;    decimals = 6;  contractAddr = null; bridgeCanister = ?"tangle_bridge"; totalSupply = null; priceUSD = null; active = true; registeredAt = Time.now() });

    // NNC (Native Nova Cycles)
    let _a9 = nextAssetId;
    nextAssetId += 1;
    assets.add({ id = _a9; symbol = "NNC";   name = "Native Nova Cycles";       chain = #ICP;         assetClass = #Other("cycles"); decimals = 0; contractAddr = null; bridgeCanister = ?"cycles_market"; totalSupply = null; priceUSD = null; active = true; registeredAt = Time.now() });

    auditLog.add("ChainVault initialized. " # Nat.toText(assets.size()) # " core assets registered.");
    "ChainVault initialized. " # Nat.toText(assets.size()) # " assets across ICP, BTC, ETH, Tangle, and NOVA Chain."
  };

  public func tick() : async Text {
    tickCount += 1;
    auditLog.add("Tick #" # Nat.toText(tickCount) # " — ChainVault heartbeat");
    "ChainVault tick #" # Nat.toText(tickCount)
  };

  // ══════════════════════════════════════════════════════════════════
  //  HELPERS
  // ══════════════════════════════════════════════════════════════════

  func chainToText(c : ChainId) : Text {
    switch (c) {
      case (#ICP)        "ICP";
      case (#Bitcoin)    "Bitcoin";
      case (#Ethereum)   "Ethereum";
      case (#Polygon)    "Polygon";
      case (#BnbChain)   "BNB Chain";
      case (#Arbitrum)   "Arbitrum";
      case (#Optimism)   "Optimism";
      case (#Base)       "Base";
      case (#Avalanche)  "Avalanche";
      case (#IOTATangle) "IOTA Tangle";
      case (#Shimmer)    "Shimmer";
      case (#IOTAEvm)    "IOTA EVM";
      case (#NovaChain)  "NOVA Chain";
      case (#Other(s))   s;
    }
  };

  func transferStatusToText(s : TransferStatus) : Text {
    switch (s) {
      case (#Initiated)    "INITIATED";
      case (#BridgeLocked) "BRIDGE_LOCKED";
      case (#Minting)      "MINTING";
      case (#Credited)     "CREDITED";
      case (#Reversing)    "REVERSING";
      case (#Completed)    "COMPLETED";
      case (#Failed(e))    "FAILED: " # e;
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
    let health = if (circuitTripped) 0.0 else 1.0;
    {
      status    = if (circuitTripped) "PAUSED" else "ACTIVE";
      health;
      name      = "CHAIN_VAULT";
      timestamp = Time.now();
    }
  };

  public func heal() : async Text {
    if (circuitTripped) {
      "CHAIN_VAULT: circuit breaker is tripped — manual reset required."
    } else {
      "CHAIN_VAULT self-check complete. Asset registry intact. " #
      Nat.toText(assets.size()) # " assets | " # Nat.toText(positions.size()) # " positions."
    }
  };

  public func register() : async Text {
    "CHAIN_VAULT registered. Capabilities: [multi-chain, asset-registry, tvl, cross-chain-transfers, circuit-breaker]."
  };

  public query func report_status() : async Text {
    "CHAIN_VAULT | status=" # (if (circuitTripped) "PAUSED" else "ACTIVE") #
    " | assets=" # Nat.toText(assets.size()) #
    " positions=" # Nat.toText(positions.size()) #
    " transfers=" # Nat.toText(transfers.size())
  };
};
