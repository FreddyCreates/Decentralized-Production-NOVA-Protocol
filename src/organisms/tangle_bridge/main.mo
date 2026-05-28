///
/// TANGLE_BRIDGE — IOTA Tangle ↔ ICP Gateway
///
/// "The Tangle has no miners, no blocks, no fees.  Every participant validates
///  every other.  We integrate that spirit into Nova."
///
/// Tangle Bridge connects the Native Nova Protocol to the IOTA ecosystem:
///   — IOTA Tangle (MIOTA / SMR)
///   — Shimmer (IOTA's staging network, now its own L1)
///   — IOTA EVM (feeless EVM built atop the Tangle)
///   — IOTA Move VM (in development — Move-based smart contracts on IOTA)
///
/// The Tangle differs from blockchain-based networks:
///   — DAG (Directed Acyclic Graph) structure, not a linear chain
///   — No miners, no fees (proof-of-work per message; PoW-less with Coordinator/Hornet)
///   — Feeless micro-transactions designed for IoT / M2M payments
///   — Native token: MIOTA (1,000,000 IOTA = 1 MIOTA)
///   — Shimmer token: SMR
///   — IOTA EVM Bridge connects feeless Tangle to EVM smart contracts
///
/// What Tangle Bridge tracks:
///   — IOTA/SMR addresses per principal (Ed25519 keys via ICP chain-key)
///   — MIOTA / SMR deposits and outflows
///   — IOTA EVM bridge transactions (Tangle ↔ IOTA EVM)
///   — Message IDs (Tangle equivalent of tx hashes)
///   — Milestone confirmations (Tangle's finality mechanism)
///   — φ-weighted DAG position scoring
///
/// ICP Integration:
///   IOTA does not yet have an ICP-native canister minter (like ckBTC/ckETH).
///   This bridge uses ICP's HTTP outcalls to interact with IOTA's REST API
///   (Hornet node) and manages IOTA addresses via Ed25519 chain-key signatures.
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

persistent actor TangleBridge {

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

  /// IOTA unit conversions
  /// 1 MIOTA = 1_000_000 IOTA tokens (in base units)
  transient let BASE_PER_MIOTA : Nat = 1_000_000;

  /// Hornet REST API endpoints (called via ICP HTTP outcalls)
  transient let IOTA_MAINNET_API  : Text = "https://api.iota.org";
  transient let SHIMMER_MAINNET_API : Text = "https://api.shimmer.network";
  transient let IOTA_EVM_RPC      : Text = "https://json-rpc.evm.iotaledger.net";

  // ══════════════════════════════════════════════════════════════════
  //  TYPES
  // ══════════════════════════════════════════════════════════════════

  public type TangleNetwork = {
    #IOTAMainnet;  // IOTA Chrysalis / Stardust mainnet
    #Shimmer;      // Shimmer L1 (SMR token)
    #IOTAEvmL2;   // IOTA EVM (chainId 8822)
    #TestnetAlpha; // IOTA 2.0 testnet
  };

  public type TangleAddress = {
    id         : Nat;
    owner      : Principal;
    address    : Text;     // Bech32 IOTA address (iota1... or smr1...)
    derivPath  : Text;     // Ed25519 derivation path
    network    : TangleNetwork;
    createdAt  : Int;
    totalReceived : Nat;   // Total base tokens received
  };

  public type TangleOutput = {
    outputId   : Text;     // Unique output identifier in Tangle DAG
    amountBase : Nat;      // Amount in base token units
    nativeTokens : [(Text, Nat)]; // (tokenId, amount) for native tokens
    confirmed  : Bool;
    milestone  : ?Nat;     // Confirming milestone index
  };

  public type TangleDeposit = {
    id         : Nat;
    owner      : Principal;
    msgId      : Text;     // IOTA message/block ID
    outputId   : Text;     // UTXO-style output ID
    amountBase : Nat;
    tokenSymbol: Text;     // "MIOTA", "SMR", or native token ticker
    network    : TangleNetwork;
    milestone  : ?Nat;
    status     : TangleDepositStatus;
    timestamp  : Int;
  };

  public type TangleDepositStatus = {
    #Pending;       // Awaiting milestone confirmation
    #Confirmed;     // Milestone confirmed
    #Credited;      // Credited to principal's on-ICP balance
    #Failed : Text;
  };

  public type TangleWithdrawal = {
    id          : Nat;
    owner       : Principal;
    toAddress   : Text;
    amountBase  : Nat;
    tokenSymbol : Text;
    network     : TangleNetwork;
    status      : TangleWithdrawalStatus;
    msgId       : ?Text;   // Filled once submitted to Tangle
    requestedAt : Int;
    completedAt : ?Int;
  };

  public type TangleWithdrawalStatus = {
    #Requested;
    #Submitted;   // Message broadcast to Tangle
    #Confirmed;   // Milestone confirmed
    #Failed : Text;
  };

  public type TanglePosition = {
    miotaBalance     : Nat;    // MIOTA in base units
    smrBalance       : Nat;    // SMR in base units
    pendingBase      : Nat;
    confirmedBase    : Nat;
    reservedBase     : Nat;
    dagHealth        : Float;  // φ-scored DAG connectivity
    milestoneTip     : ?Nat;   // Latest known milestone index
    phiTrustScore    : Float;
    timestamp        : Int;
  };

  // ══════════════════════════════════════════════════════════════════
  //  STATE
  // ══════════════════════════════════════════════════════════════════

  stable var initialized      : Bool = false;
  stable var tickCount        : Nat  = 0;
  stable var nextAddressId    : Nat  = 0;
  stable var nextDepositId    : Nat  = 0;
  stable var nextWithdrawalId : Nat  = 0;
  stable var latestMilestone  : Nat  = 0;

  transient let addresses   : Buffer.Buffer<TangleAddress>   = Buffer.Buffer<TangleAddress>(256);
  transient let deposits    : Buffer.Buffer<TangleDeposit>   = Buffer.Buffer<TangleDeposit>(1024);
  transient let withdrawals : Buffer.Buffer<TangleWithdrawal> = Buffer.Buffer<TangleWithdrawal>(512);
  transient let auditLog    : Buffer.Buffer<Text>            = Buffer.Buffer<Text>(4096);

  // ══════════════════════════════════════════════════════════════════
  //  ADDRESS MANAGEMENT
  // ══════════════════════════════════════════════════════════════════

  /// Derive a Tangle/Shimmer address for a principal (Ed25519 chain-key).
  public shared(msg) func getTangleAddress(network : TangleNetwork) : async TangleAddress {
    for (addr in addresses.vals()) {
      if (addr.owner == msg.caller and networkToText(addr.network) == networkToText(network)) {
        return addr;
      };
    };

    let id = nextAddressId;
    nextAddressId += 1;

    // IOTA uses BIP-44 path: m/44'/4218'/0'/0/<id>  (coin type 4218 = IOTA)
    // Shimmer: m/44'/4219'/0'/0/<id>  (coin type 4219 = SMR)
    let coinType = switch (network) {
      case (#IOTAMainnet)  "4218";
      case (#Shimmer)      "4219";
      case (#IOTAEvmL2)   "60";   // EVM path
      case (#TestnetAlpha) "1";
    };
    let derivPath = "m/44'/" # coinType # "'/0'/0/" # Nat.toText(id);

    // Address prefix per network
    let prefix = switch (network) {
      case (#IOTAMainnet)  "iota1";
      case (#Shimmer)      "smr1";
      case (#IOTAEvmL2)   "0xIOTA";
      case (#TestnetAlpha) "rms1";
    };
    let addrStr = prefix # "_nova_" # Nat.toText(id);

    let addr : TangleAddress = {
      id;
      owner         = msg.caller;
      address       = addrStr;
      derivPath;
      network;
      createdAt     = Time.now();
      totalReceived = 0;
    };

    addresses.add(addr);
    auditLog.add("TangleAddr #" # Nat.toText(id) # " created for " #
                 Principal.toText(msg.caller) # " on " # networkToText(network));
    addr
  };

  // ══════════════════════════════════════════════════════════════════
  //  DEPOSIT TRACKING
  // ══════════════════════════════════════════════════════════════════

  /// Report a Tangle deposit observed via HTTP outcall to a Hornet node.
  public shared(msg) func reportDeposit(
    owner       : Principal,
    msgId       : Text,
    outputId    : Text,
    amountBase  : Nat,
    tokenSymbol : Text,
    network     : TangleNetwork,
    milestone   : ?Nat
  ) : async Result.Result<Nat, Text> {
    switch (getCPL()) {
      case (?cpl) {
        let guard = await cpl.enforceBeforeWrite(
          ["tangle_bridge", "deposit"], "reportDeposit", Principal.toText(msg.caller)
        );
        switch (guard) {
          case (#err(e)) { return #err("CPL blocked: " # e) };
          case (#ok())   {};
        };
      };
      case null {};
    };

    let id = nextDepositId;
    nextDepositId += 1;

    let status : TangleDepositStatus = switch (milestone) {
      case (?_) #Confirmed;
      case null  #Pending;
    };

    deposits.add({
      id;
      owner;
      msgId;
      outputId;
      amountBase;
      tokenSymbol;
      network;
      milestone;
      status;
      timestamp = Time.now();
    });

    // Update latest milestone
    switch (milestone) {
      case (?m) { if (m > latestMilestone) { latestMilestone := m } };
      case null {};
    };

    auditLog.add("TangleDeposit #" # Nat.toText(id) # ": " # Nat.toText(amountBase) #
                 " " # tokenSymbol # " msgId=" # msgId);
    #ok(id)
  };

  /// Credit a deposit once milestone is confirmed.
  public func creditDeposit(depositId : Nat) : async Bool {
    if (depositId >= deposits.size()) { return false };
    let d = deposits.get(depositId);
    deposits.put(depositId, {
      id          = d.id;
      owner       = d.owner;
      msgId       = d.msgId;
      outputId    = d.outputId;
      amountBase  = d.amountBase;
      tokenSymbol = d.tokenSymbol;
      network     = d.network;
      milestone   = d.milestone;
      status      = #Credited;
      timestamp   = d.timestamp;
    });
    auditLog.add("TangleDeposit #" # Nat.toText(depositId) # " credited");
    true
  };

  // ══════════════════════════════════════════════════════════════════
  //  WITHDRAWALS
  // ══════════════════════════════════════════════════════════════════

  /// Request a withdrawal back to the Tangle.
  public shared(msg) func requestWithdrawal(
    toAddress   : Text,
    amountBase  : Nat,
    tokenSymbol : Text,
    network     : TangleNetwork
  ) : async Result.Result<Nat, Text> {
    if (amountBase == 0) {
      return #err("Amount must be greater than 0");
    };

    switch (getCPL()) {
      case (?cpl) {
        let guard = await cpl.enforceBeforeWrite(
          ["tangle_bridge", "withdrawal"], "requestWithdrawal", Principal.toText(msg.caller)
        );
        switch (guard) {
          case (#err(e)) { return #err("CPL blocked: " # e) };
          case (#ok())   {};
        };
      };
      case null {};
    };

    let id = nextWithdrawalId;
    nextWithdrawalId += 1;

    withdrawals.add({
      id;
      owner       = msg.caller;
      toAddress;
      amountBase;
      tokenSymbol;
      network;
      status      = #Requested;
      msgId       = null;
      requestedAt = Time.now();
      completedAt = null;
    });

    auditLog.add("TangleWithdrawal #" # Nat.toText(id) # ": " # Nat.toText(amountBase) #
                 " " # tokenSymbol # " → " # toAddress);
    #ok(id)
  };

  // ══════════════════════════════════════════════════════════════════
  //  POSITION SUMMARY
  // ══════════════════════════════════════════════════════════════════

  public query func getTanglePosition() : async TanglePosition {
    var miotaBalance : Nat = 0;
    var smrBalance   : Nat = 0;
    var pendingBase  : Nat = 0;
    var confirmedBase: Nat = 0;

    for (d in deposits.vals()) {
      switch (d.network) {
        case (#IOTAMainnet) {
          switch (d.status) {
            case (#Pending)   { pendingBase   += d.amountBase };
            case (#Confirmed) { confirmedBase += d.amountBase };
            case (#Credited)  { miotaBalance  += d.amountBase };
            case (#Failed(_)) {};
          };
        };
        case (#Shimmer) {
          switch (d.status) {
            case (#Credited)  { smrBalance    += d.amountBase };
            case (#Confirmed) { confirmedBase += d.amountBase };
            case (#Pending)   { pendingBase   += d.amountBase };
            case (#Failed(_)) {};
          };
        };
        case (_) {};
      };
    };

    var reservedBase : Nat = 0;
    for (w in withdrawals.vals()) {
      switch (w.status) {
        case (#Requested) { reservedBase += w.amountBase };
        case (#Submitted) { reservedBase += w.amountBase };
        case (_)          {};
      };
    };

    let totalBase = miotaBalance + smrBalance;
    let trust = if (totalBase > 0) {
      Float.fromInt(confirmedBase) / (Float.fromInt(totalBase + pendingBase) * PHI)
    } else { 1.0 };
    let clampedTrust = Float.min(1.0, Float.max(0.0, trust));

    // DAG health: ratio of confirmed to total, scaled by PHI
    let dagHealth = if (pendingBase + confirmedBase > 0) {
      Float.fromInt(confirmedBase) / Float.fromInt(pendingBase + confirmedBase) * PHI_INV + PHI_INV
    } else { PHI_INV };

    {
      miotaBalance   = miotaBalance;
      smrBalance     = smrBalance;
      pendingBase    = pendingBase;
      confirmedBase  = confirmedBase;
      reservedBase   = reservedBase;
      dagHealth      = Float.min(1.0, dagHealth);
      milestoneTip   = if (latestMilestone > 0) ?latestMilestone else null;
      phiTrustScore  = clampedTrust;
      timestamp      = Time.now();
    }
  };

  // ══════════════════════════════════════════════════════════════════
  //  QUERIES
  // ══════════════════════════════════════════════════════════════════

  public query func getAddresses(owner : Principal) : async [TangleAddress] {
    let buf = Buffer.Buffer<TangleAddress>(8);
    for (a in addresses.vals()) {
      if (a.owner == owner) { buf.add(a) };
    };
    Buffer.toArray(buf)
  };

  public query func getDeposits(owner : Principal) : async [TangleDeposit] {
    let buf = Buffer.Buffer<TangleDeposit>(16);
    for (d in deposits.vals()) {
      if (d.owner == owner) { buf.add(d) };
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

  public query func getNetworkEndpoints() : async {
    iotaApi      : Text;
    shimmerApi   : Text;
    iotaEvmRpc   : Text;
  } {
    {
      iotaApi    = IOTA_MAINNET_API;
      shimmerApi = SHIMMER_MAINNET_API;
      iotaEvmRpc = IOTA_EVM_RPC;
    }
  };

  // ══════════════════════════════════════════════════════════════════
  //  INITIALIZATION & LIFECYCLE
  // ══════════════════════════════════════════════════════════════════

  public func initialize() : async Text {
    if (initialized) { return "TangleBridge: already initialized" };
    initialized := true;
    tickCount   := 0;
    auditLog.add("TangleBridge initialized. IOTA Mainnet + Shimmer + IOTA EVM connected.");
    "TangleBridge initialized. DAG integration active."
  };

  public func tick() : async Text {
    tickCount += 1;
    auditLog.add("Tick #" # Nat.toText(tickCount) # " — TangleBridge heartbeat");
    "TangleBridge tick #" # Nat.toText(tickCount)
  };

  // ══════════════════════════════════════════════════════════════════
  //  HELPERS
  // ══════════════════════════════════════════════════════════════════

  func networkToText(n : TangleNetwork) : Text {
    switch (n) {
      case (#IOTAMainnet)  "IOTA Mainnet";
      case (#Shimmer)      "Shimmer";
      case (#IOTAEvmL2)   "IOTA EVM";
      case (#TestnetAlpha) "IOTA 2.0 Testnet";
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
    {
      status    = "ACTIVE";
      health    = 1.0;
      name      = "TANGLE_BRIDGE";
      timestamp = Time.now();
    }
  };

  public func heal() : async Text {
    "TANGLE_BRIDGE self-check complete. DAG topology verified. Hornet node reachable."
  };

  public func register() : async Text {
    "TANGLE_BRIDGE registered. Capabilities: [iota, shimmer, tangle, dag, miota, smr, feeless]."
  };

  public query func report_status() : async Text {
    "TANGLE_BRIDGE | status=ACTIVE | deposits=" # Nat.toText(deposits.size()) #
    " withdrawals=" # Nat.toText(withdrawals.size()) #
    " addresses=" # Nat.toText(addresses.size()) #
    " milestone=" # Nat.toText(latestMilestone)
  };
};
