import { CreatePoolParams, LiquidatePositionParams, ModifyPositionParams, Protocol, calculateRates } from ".";

type OmitPool<T> = Omit<T, "pool_id" | "user" | "receive_as_shares">;

export class Pool {
  constructor(
    public id: bigint,
    public protocol: Protocol,
    public params: CreatePoolParams,
  ) {}

  async lend({ collateral_asset, debt_asset, collateral, debt, data }: OmitPool<ModifyPositionParams>) {
    const { deployer, singleton } = this.protocol;
    const params: ModifyPositionParams = {
      pool_id: this.id,
      collateral_asset,
      debt_asset,
      user: deployer.lender.address,
      collateral,
      debt,
      data,
    };
    singleton.connect(deployer.lender);
    const response = await singleton.modify_position(params);
    return response;
  }

  async borrow({ collateral_asset, debt_asset, collateral, debt, data }: OmitPool<ModifyPositionParams>) {
    const { deployer, singleton } = this.protocol;
    const params: ModifyPositionParams = {
      pool_id: this.id,
      collateral_asset,
      debt_asset,
      user: deployer.borrower.address,
      collateral,
      debt,
      data,
    };
    singleton.connect(deployer.borrower);
    const response = await singleton.modify_position(params);
    return response;
  }

  async liquidate({ collateral_asset, debt_asset, data }: OmitPool<LiquidatePositionParams>) {
    const { deployer, singleton } = this.protocol;
    const params: LiquidatePositionParams = {
      pool_id: this.id,
      collateral_asset,
      debt_asset,
      user: deployer.borrower.address,
      receive_as_shares: false,
      data,
    };
    singleton.connect(deployer.lender);
    const response = await singleton.liquidate_position(params);
    return response;
  }

  async borrowAndSupplyRates(assetAddress: string) {
    const index = this.params.asset_params.findIndex(({ asset }) => asset === assetAddress);
    const config = this.params.interest_rate_configs[index];
    return await calculateRates(this.protocol, this.id, assetAddress, config);
  }
}
