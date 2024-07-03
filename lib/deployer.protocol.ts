import assert from "assert";
import { unzip } from "lodash-es";
import { Account, Call, CallData, Contract, RpcProvider } from "starknet";
import { BaseDeployer, Config, Protocol, logAddresses } from ".";

export interface ProtocolContracts {
  singleton: Contract;
  extension: Contract;
  oracle: Contract;
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
    const [protocolContracts, protocolCalls] = await this.deferProtocol(envContracts.oracle.address);
    let response = await this.execute([...envCalls, ...protocolCalls]);
    await this.waitForTransaction(response.transaction_hash);
    const contracts = { ...protocolContracts, ...envContracts };
    await this.setApprovals(contracts.singleton, contracts.assets);
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
      extension: await this.loadContract(protocol.extension!),
      oracle: await this.loadContract(protocol.oracle!),
      assets: await Promise.all(addresses),
    };
    logAddresses("Loaded:", contracts);
    return Protocol.from(contracts, this);
  }

  async deployProtocol(oracleAddress: string) {
    const [contracts, calls] = await this.deferProtocol(oracleAddress);
    const response = await this.execute([...calls]);
    await this.waitForTransaction(response.transaction_hash);
    return [contracts, response] as const;
  }

  async deferProtocol(oracleAddress: string) {
    const [singleton, calls1] = await this.deferContract("Singleton");
    const v_token_class_hash = await this.declareCached("VToken");
    const calldata = CallData.compile({
      singleton: singleton.address,
      oracle_address: oracleAddress,
      v_token_class_hash: v_token_class_hash,
    });
    const [extension, calls2] = await this.deferContract("DefaultExtension", calldata);
    return [{ singleton, extension }, [...calls1, ...calls2]] as const;
  }

  async deployEnv() {
    const [contracts, calls] = await this.deferEnv();
    const response = await this.execute([...calls]);
    await this.waitForTransaction(response.transaction_hash);
    return [contracts, response] as const;
  }

  async deferEnv() {
    const [assets, assetCalls] = await this.deferMockAssets(this.lender.address);
    const [oracle, oracleCalls] = await this.deferOracle();
    return [{ assets, oracle }, [...assetCalls, ...oracleCalls]] as const;
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

  async deferOracle() {
    const [oracle, calls] = await this.deferContract("MockPragmaOracle");
    const setupCalls = this.config.env!.map(({ pragmaKey, price }) =>
      oracle.populateTransaction.set_price(pragmaKey, price),
    );
    return [oracle, [...calls, ...setupCalls]] as const;
  }

  async setApprovals(singleton: Contract, assets: Contract[]) {
    const approvalCalls = assets.map((asset, index) => {
      const { initial_supply } = this.config.env![index].erc20Params();
      return asset.populateTransaction.approve(singleton.address, initial_supply);
    });
    let response = await this.lender.execute(approvalCalls);
    await this.waitForTransaction(response.transaction_hash);
    response = await this.borrower.execute(approvalCalls);
    await this.waitForTransaction(response.transaction_hash);
  }
}
