import fs from "fs";
import { shortString } from "starknet";
import { setup } from "../lib";

const deployer = await setup("devnet");
const protocol = await deployer.deployEnvAndProtocol();

const deployment = {
  singleton: protocol.singleton.address,
  extensionPO: protocol.extensionPO.address,
  extensionCL: protocol.extensionCL.address,
  pragma: {
    oracle: protocol.pragma.oracle.address,
    summary_stats: protocol.pragma.summary_stats.address,
  },
  assets: protocol.assets.map((asset) => asset.address),
  pools: [],
};

fs.writeFileSync(
  `deployment_${shortString.decodeShortString(await deployer.provider.getChainId()).toLowerCase()}.json`,
  JSON.stringify(deployment, null, 2),
);
