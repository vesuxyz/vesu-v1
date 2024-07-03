import { isEmpty } from "lodash-es";
import { setup } from "../lib";

const deployer = await setup(process.env.NETWORK);

const protocol = await deployer.loadProtocol();

const pools = Object.keys(deployer.config.pools);
if (isEmpty(pools)) {
  throw new Error("No pools to create in config");
}

for (const name of pools) {
  console.log("Creating pool:", name);
  const [pool, response] = await protocol.createPool(name);
  console.log("Created tx:", response.transaction_hash);
  console.log("Created pool id:", pool.id);
  console.log("Created pool params:", pool.params);
  console.dir(pool.params, { depth: null });
}
