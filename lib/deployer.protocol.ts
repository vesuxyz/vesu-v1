import assert from "assert";
import { unzip } from "lodash-es";
import { Account, Call, CallData, Contract, RpcProvider } from "starknet";
import { BaseDeployer, Config, Protocol, logAddresses } from ".";

export interface PragmaConfig {
  oracle: string | undefined;
  summary_stats: string | undefined;
}

export interface PragmaContracts {
  oracle: Contract;
  summary_stats: Contract;
}

export interface ProtocolContracts {
  singleton: Contract;
  extensionPO: Contract;
  extensionCL: Contract;
  pragma: PragmaContracts;
  assets: Contract[];
}

export class Deployer extends BaseDeployer {
  constructor(
    public provider: RpcProvider,
    account: Account,
    public config: Config,
    public creator: Account,
    public lender: Account,
    public borrower: Account,
  ) {
    super(provider, account);
  }

  async deployEnvAndProtocol(): Promise<Protocol> {
    assert(this.config.env, "Test environment not defined, use loadProtocol for existing networks");
    const [envContracts, envCalls] = await this.deferEnv();
    const pragma = {
      oracle: envContracts.pragma.oracle.address,
      summary_stats: envContracts.pragma.summary_stats.address,
    };
    const [protocolContracts, protocolCalls] = await this.deferProtocol(pragma);
    let response = await this.execute([...envCalls, ...protocolCalls]);
    await this.waitForTransaction(response.transaction_hash);
    const contracts = { ...protocolContracts, ...envContracts };
    await this.setApprovals(contracts.singleton, contracts.assets);
    await this.setApprovals(contracts.extensionPO, contracts.assets);
    await this.setApprovals(contracts.extensionCL, contracts.assets);
    logAddresses("Deployed:", contracts);
    return Protocol.from(contracts, this);
  }

  async loadProtocol(): Promise<Protocol> {
    const { protocol, pools } = this.config;
    const addresses = Object.values(pools)
      .flatMap(({ params }) => params.asset_params.map(({ asset }) => asset))
      .map(this.loadContract.bind(this));
    const contracts = {
      singleton: await this.loadContract(protocol.singleton!),
      extensionPO: await this.loadContract(protocol.extensionPO!),
      extensionCL: await this.loadContract(protocol.extensionCL!),
      pragma: {
        oracle: await this.loadContract(protocol.pragma.oracle!),
        summary_stats: await this.loadContract(protocol.pragma.summary_stats!),
      },
      assets: await Promise.all(addresses),
    };
    logAddresses("Loaded:", contracts);
    return Protocol.from(contracts, this);
  }

  async deployProtocol(pragma: PragmaConfig) {
    const [contracts, calls] = await this.deferProtocol(pragma);
    const response = await this.execute([...calls]);
    await this.waitForTransaction(response.transaction_hash);
    return [contracts, response] as const;
  }

  async deferProtocol(pragma: PragmaConfig) {
    const [singleton, calls1] = await this.deferContract("Singleton");
    const v_token_class_hash = await this.declareCached("VToken");
    const calldataPO = CallData.compile({
      singleton: singleton.address,
      oracle_address: pragma.oracle!,
      summary_stats_address: pragma.summary_stats!,
      v_token_class_hash: v_token_class_hash,
    });
    const [extensionPO, calls2] = await this.deferContract("DefaultExtensionPO", calldataPO);
    const calldataCL = CallData.compile({
      singleton: singleton.address,
      v_token_class_hash: v_token_class_hash,
    });
    const [extensionCL, calls3] = await this.deferContract("DefaultExtensionCL", calldataCL);
    return [{ singleton, extensionPO, extensionCL }, [...calls1, ...calls2, ...calls3]] as const;
  }

  async deployEnv() {
    const [contracts, calls] = await this.deferEnv();
    const response = await this.execute([...calls]);
    await this.waitForTransaction(response.transaction_hash);
    return [contracts, response] as const;
  }

  async deferEnv() {
    const [assets, assetCalls] = await this.deferMockAssets(this.lender.address);
    const [oracle, summary_stats, pragmaCalls] = await this.deferPragmaOracle();
    return [{ assets, pragma: { oracle, summary_stats } }, [...assetCalls, ...pragmaCalls]] as const;
  }

  async deferMockAssets(recipient: string) {
    // first asset declared separately to avoid out of memory on CI
    const [first, ...rest] = this.config.env!;

    const calldata = CallData.compile({ ...first.erc20Params(), recipient });
    const [asset0, calls0] = await this.deferContract("MockAsset", calldata);
    const promises = rest.map((params) =>
      this.deferContract("MockAsset", CallData.compile({ ...params.erc20Params(), recipient })),
    );
    const [otherAssets, otherCalls] = unzip(await Promise.all(promises));

    const assets = [asset0, ...otherAssets] as Contract[];
    const calls = [...calls0, ...otherCalls.flat()] as Call[];
    return [assets, calls] as const;
  }

  async deferPragmaOracle() {
    const [oracle, oracleCalls] = await this.deferContract("MockPragmaOracle");
    const [summary_stats, summaryStatsCalls] = await this.deferContract("MockPragmaSummary");
    const setupCalls = this.config.env!.map(({ pragmaKey, price }) =>
      oracle.populateTransaction.set_price(pragmaKey, price),
    );
    return [oracle, summary_stats, [...oracleCalls, ...summaryStatsCalls, ...setupCalls]] as const;
  }

  async setApprovals(contract: Contract, assets: Contract[]) {
    const approvalCalls = assets.map((asset, index) => {
      const { initial_supply } = this.config.env![index].erc20Params();
      return asset.populateTransaction.approve(contract.address, initial_supply);
    });
    let response = await this.creator.execute(approvalCalls);
    await this.waitForTransaction(response.transaction_hash);
    response = await this.lender.execute(approvalCalls);
    await this.waitForTransaction(response.transaction_hash);
    response = await this.borrower.execute(approvalCalls);
    await this.waitForTransaction(response.transaction_hash);

    // transfer INFLATION_FEE to creator
    const transferCalls = assets.map((asset, index) => {
      return asset.populateTransaction.transfer(this.creator.address, 2000);
    });
    response = await this.lender.execute(transferCalls);
    await this.waitForTransaction(response.transaction_hash);
  }
}
