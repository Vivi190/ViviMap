#!/usr/bin/env node
// App Store provisioning through the App Store Connect API: no Mac and no Apple ID login needed.
// Run once for setup and again yearly when the distribution certificate expires.
//
//   node Tools/appstore/provision.mjs --key ~/atlas-signing/AuthKey_XXXX.p8 --issuer <issuer-id> \
//        --csr ~/atlas-signing/dist.csr --out ~/atlas-signing [--bundle com.vivimap.atlas] [--steps bundle,cert,profile,testflight]
//
// Needs a Team API key with the Admin role (provisioning endpoints). Prints ids only, never key material.
import { createPrivateKey, sign } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import { basename, join } from "node:path";

const args = {};
process.argv.slice(2).forEach((value, i, all) => {
  if (value.startsWith("--")) args[value.slice(2)] = all[i + 1];
});
const keyPath = args.key;
const keyId = args["key-id"] ?? basename(keyPath ?? "").match(/AuthKey_(\w+)\.p8$/)?.[1];
const issuer = args.issuer;
const bundle = args.bundle ?? "com.vivimap.atlas";
const out = args.out ?? ".";
const steps = (args.steps ?? "bundle,cert,profile").split(",");
if (!keyPath || !keyId || !issuer) {
  console.error("usage: --key AuthKey_<KEYID>.p8 --issuer <issuer-id> [--csr dist.csr] [--out dir] [--steps ...]");
  process.exit(2);
}
const privateKey = createPrivateKey(readFileSync(keyPath));

function token() {
  const now = Math.floor(Date.now() / 1000);
  const encode = (obj) => Buffer.from(JSON.stringify(obj)).toString("base64url");
  const unsigned = `${encode({ alg: "ES256", kid: keyId, typ: "JWT" })}.${encode({ iss: issuer, iat: now, exp: now + 1100, aud: "appstoreconnect-v1" })}`;
  const signature = sign("sha256", Buffer.from(unsigned), { key: privateKey, dsaEncoding: "ieee-p1363" });
  return `${unsigned}.${signature.toString("base64url")}`;
}

async function api(method, path, body) {
  const response = await fetch(`https://api.appstoreconnect.apple.com${path}`, {
    method,
    headers: { Authorization: `Bearer ${token()}`, "Content-Type": "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  });
  const json = response.status === 204 ? {} : await response.json();
  if (!response.ok) {
    const detail = (json.errors ?? []).map((e) => `${e.code}: ${e.detail ?? e.title}`).join("; ");
    throw new Error(`${method} ${path} -> ${response.status} ${detail}`);
  }
  return json;
}

async function ensureBundleId() {
  const found = await api("GET", `/v1/bundleIds?filter[identifier]=${encodeURIComponent(bundle)}&limit=5`);
  const exact = found.data.find((b) => b.attributes.identifier === bundle);
  if (exact) {
    console.log(`bundle id exists: ${bundle} (${exact.id})`);
    return exact.id;
  }
  const created = await api("POST", "/v1/bundleIds", {
    data: { type: "bundleIds", attributes: { identifier: bundle, name: "Atlas", platform: "IOS" } },
  });
  console.log(`bundle id registered: ${bundle} (${created.data.id})`);
  return created.data.id;
}

async function createCertificate() {
  const csr = readFileSync(args.csr, "utf8");
  const created = await api("POST", "/v1/certificates", {
    data: { type: "certificates", attributes: { certificateType: "DISTRIBUTION", csrContent: csr } },
  });
  const path = join(out, "distribution.cer");
  writeFileSync(path, Buffer.from(created.data.attributes.certificateContent, "base64"));
  console.log(`certificate created: ${created.data.attributes.name} (${created.data.id}), expires ${created.data.attributes.expirationDate} -> ${path}`);
  return created.data.id;
}

async function createProfile(bundleId, certificateId) {
  const name = `Atlas AppStore ${new Date().toISOString().slice(0, 10)}`;
  const created = await api("POST", "/v1/profiles", {
    data: {
      type: "profiles",
      attributes: { name, profileType: "IOS_APP_STORE" },
      relationships: {
        bundleId: { data: { type: "bundleIds", id: bundleId } },
        certificates: { data: [{ type: "certificates", id: certificateId }] },
      },
    },
  });
  const path = join(out, "Atlas_AppStore.mobileprovision");
  writeFileSync(path, Buffer.from(created.data.attributes.profileContent, "base64"));
  console.log(`profile created: ${name} (${created.data.id}) -> ${path}`);
}

async function setUpTestFlight() {
  const apps = await api("GET", `/v1/apps?filter[bundleId]=${encodeURIComponent(bundle)}`);
  const app = apps.data[0];
  if (!app) throw new Error(`no App Store Connect app record for ${bundle} yet (create it in the web UI first)`);
  const groups = await api("GET", `/v1/betaGroups?filter[app]=${app.id}&filter[isInternalGroup]=true`);
  let group = groups.data[0];
  if (!group) {
    group = (await api("POST", "/v1/betaGroups", {
      data: {
        type: "betaGroups",
        attributes: { name: "Ben", isInternalGroup: true, hasAccessToAllBuilds: true },
        relationships: { app: { data: { type: "apps", id: app.id } } },
      },
    })).data;
  }
  console.log(`internal TestFlight group: ${group.attributes.name} (${group.id})`);
  const holders = await api("GET", "/v1/users?filter[roles]=ACCOUNT_HOLDER&limit=5");
  for (const user of holders.data) {
    const { username, firstName, lastName } = user.attributes;
    try {
      await api("POST", "/v1/betaTesters", {
        data: {
          type: "betaTesters",
          attributes: { email: username, firstName, lastName },
          relationships: { betaGroups: { data: [{ type: "betaGroups", id: group.id }] } },
        },
      });
      console.log("account holder added to the internal group");
    } catch (error) {
      console.log(`tester not added automatically (${error.message.split(" -> ")[1] ?? error.message})`);
    }
  }
}

let bundleId;
let certificateId;
if (steps.includes("bundle")) bundleId = await ensureBundleId();
if (steps.includes("cert")) certificateId = await createCertificate();
if (steps.includes("profile")) await createProfile(bundleId ?? (await ensureBundleId()), certificateId ?? args["cert-id"]);
if (steps.includes("testflight")) await setUpTestFlight();
