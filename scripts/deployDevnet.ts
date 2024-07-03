import fs from "fs";
import { shortString } from "starknet";
import { setup } from "../lib";

const deployer = await setup("devnet");
const protocol = await deployer.deployEnvAndProtocol();

const deployment = {
  singleton: protocol.singleton.address,
  extension: protocol.extension.address,
  oracle: protocol.oracle.address,
  assets: protocol.assets.map((asset) => asset.address),
  pools: [],
};

fs.writeFileSync(
  `deployment_${shortString.decodeShortString(await deployer.provider.getChainId()).toLowerCase()}.json`,
  JSON.stringify(deployment, null, 2),
);
