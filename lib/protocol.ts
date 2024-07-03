import assert from "assert";
import { Contract } from "starknet";
import { CreatePoolParams, Deployer, Pool, ProtocolContracts } from ".";

export class Protocol implements ProtocolContracts {
  constructor(
    public singleton: Contract,
    public extension: Contract,
    public oracle: Contract,
    public assets: Contract[],
    public deployer: Deployer,
  ) {}

  static from(contracts: ProtocolContracts, deployer: Deployer) {
    const { singleton, extension, oracle, assets } = contracts;
    return new Protocol(singleton, extension, oracle, assets, deployer);
  }

  async createPool(name: string, { devnetEnv = false, printParams = false } = {}) {
    let { params } = this.deployer.config.pools[name];
    if (devnetEnv) {
      params = this.patchPoolParamsWithEnv(params);
      if (printParams) {
        console.log("Pool params:");
        console.dir(params, { depth: null });
      }
    }
    return this.createPoolFromParams(params);
  }

  async createPoolFromParams(params: CreatePoolParams) {
    const { singleton, extension, deployer } = this;
    const nonce = await singleton.creator_nonce(extension.address);
    const poolId = await singleton.calculate_pool_id(extension.address, nonce);
    assert((await singleton.pools(poolId)) === 0n, "pool_id is 0");

    extension.connect(deployer.creator);
    const response = await extension.create_pool(
      params.asset_params,
      params.max_position_ltv_params,
      params.interest_rate_models,
      params.pragma_oracle_params,
      params.liquidation_params,
      params.shutdown_params,
    );
    await deployer.waitForTransaction(response.transaction_hash);

    assert((await singleton.pools(poolId)) !== 0n, "pool_id shouldn't be 0");
    const pool = new Pool(poolId, this, params);

    return [pool, response] as const;
  }

  async loadPool(name: string | 0) {
    const { config } = this.deployer;
    if (name === 0) {
      [name] = Object.keys(config.pools);
    }
    const poolConfig = config.pools[name];
    return new Pool(poolConfig.id, this, poolConfig.params);
  }

  patchPoolParamsWithEnv({ asset_params, ...others }: CreatePoolParams): CreatePoolParams {
    asset_params = asset_params.map(({ asset, ...rest }, index) => ({
      asset: this.assets[index].address,
      ...rest,
    }));
    return { asset_params, ...others };
  }
}
