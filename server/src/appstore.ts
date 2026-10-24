// Apple App 内购买（StoreKit 2）签名验证：验证 JWS 的 x5c 证书链到 Apple Root CA - G3，再用叶证书验证签名。
// 不依赖第三方库，用 WebCrypto + 简单的 DER 解析。

const APPLE_ROOT_G3_SHA256 = "63343ABFB89A6A03EBB57E9B3F5FA7BE7C4F5C756F3017B3A8C488C3653E9179";

// 叶证书与中间证书里 Apple 规定的扩展 OID（DER 编码）
const OID_LEAF = [0x06, 0x0a, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x63, 0x64, 0x06, 0x0b, 0x01];          // 1.2.840.113635.100.6.11.1
const OID_INTERMEDIATE = [0x06, 0x0a, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x63, 0x64, 0x06, 0x02, 0x01];  // 1.2.840.113635.100.6.2.1
const OID_P256 = [0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07];
const OID_P384 = [0x06, 0x05, 0x2b, 0x81, 0x04, 0x00, 0x22];
const OID_ECDSA_SHA256 = [0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x04, 0x03, 0x02];
const OID_ECDSA_SHA384 = [0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x04, 0x03, 0x03];

interface TLV {
  tag: number;
  start: number;
  hdr: number;
  len: number;
  end: number;
}

function readTLV(buf: Uint8Array, off: number): TLV {
  const tag = buf[off];
  let len = buf[off + 1];
  let hdr = 2;
  if (len & 0x80) {
    const n = len & 0x7f;
    len = 0;
    for (let i = 0; i < n; i++) len = len * 256 + buf[off + 2 + i];
    hdr = 2 + n;
  }
  return { tag, start: off, hdr, len, end: off + hdr + len };
}

function children(buf: Uint8Array, t: TLV): TLV[] {
  const out: TLV[] = [];
  let o = t.start + t.hdr;
  while (o < t.end) {
    const c = readTLV(buf, o);
    out.push(c);
    o = c.end;
  }
  return out;
}

function contains(hay: Uint8Array, needle: number[]): boolean {
  outer: for (let i = 0; i + needle.length <= hay.length; i++) {
    for (let j = 0; j < needle.length; j++) if (hay[i + j] !== needle[j]) continue outer;
    return true;
  }
  return false;
}

interface ParsedCert {
  der: Uint8Array;
  tbs: Uint8Array;
  spki: Uint8Array;
  curve: "P-256" | "P-384";
  sigHash: "SHA-256" | "SHA-384";
  signature: Uint8Array; // DER 编码的 ECDSA 签名
}

function parseCert(der: Uint8Array): ParsedCert {
  const cert = readTLV(der, 0);
  const [tbsT, algT, sigT] = children(der, cert);
  const tbs = der.subarray(tbsT.start, tbsT.end);
  const fields = children(der, tbsT);
  // tbs: [0]version, serial, sigAlg, issuer, validity, subject, spki, ...
  const offset = fields[0].tag === 0xa0 ? 1 : 0;
  const spkiT = fields[offset + 5];
  const spki = der.subarray(spkiT.start, spkiT.end);
  const curve = contains(spki, OID_P384) ? "P-384" : contains(spki, OID_P256) ? "P-256" : null;
  if (!curve) throw new Error("不支持的证书曲线");
  const alg = der.subarray(algT.start, algT.end);
  const sigHash = contains(alg, OID_ECDSA_SHA384) ? "SHA-384" : contains(alg, OID_ECDSA_SHA256) ? "SHA-256" : null;
  if (!sigHash) throw new Error("不支持的证书签名算法");
  // BIT STRING：第一个字节是未使用位数
  const signature = der.subarray(sigT.start + sigT.hdr + 1, sigT.end);
  return { der, tbs, spki, curve, sigHash, signature };
}

/** DER 的 ECDSA-Sig-Value → WebCrypto 需要的 r||s */
function derSigToRaw(sig: Uint8Array, size: number): Uint8Array {
  const seq = readTLV(sig, 0);
  const [r, s] = children(sig, seq);
  const out = new Uint8Array(size * 2);
  const put = (t: TLV, at: number) => {
    let v = sig.subarray(t.start + t.hdr, t.end);
    while (v.length > size && v[0] === 0) v = v.subarray(1);
    out.set(v, at + size - v.length);
  };
  put(r, 0);
  put(s, size);
  return out;
}

async function importKey(c: ParsedCert): Promise<CryptoKey> {
  return crypto.subtle.importKey("spki", c.spki, { name: "ECDSA", namedCurve: c.curve }, false, ["verify"]);
}

/** 用 issuer 的公钥验证 subject 证书的签名 */
async function verifyCertSignature(subject: ParsedCert, issuer: ParsedCert): Promise<boolean> {
  const key = await importKey(issuer);
  const size = issuer.curve === "P-384" ? 48 : 32;
  return crypto.subtle.verify(
    { name: "ECDSA", hash: subject.sigHash },
    key,
    derSigToRaw(subject.signature, size),
    subject.tbs,
  );
}

function b64ToBytes(s: string): Uint8Array {
  const bin = atob(s.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((s.length + 3) % 4));
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

async function sha256Hex(data: Uint8Array): Promise<string> {
  const h = new Uint8Array(await crypto.subtle.digest("SHA-256", data));
  return [...h].map((b) => b.toString(16).padStart(2, "0")).join("").toUpperCase();
}

/** 验证 Apple 签名的 JWS（交易、续订信息、服务器通知），返回 payload */
export async function verifyAppleJWS(jws: string): Promise<any> {
  const parts = jws.split(".");
  if (parts.length !== 3) throw new Error("JWS 格式错误");
  const header = JSON.parse(new TextDecoder().decode(b64ToBytes(parts[0])));
  if (header.alg !== "ES256" || !Array.isArray(header.x5c) || header.x5c.length < 3) throw new Error("JWS 头不正确");

  const [leaf, intermediate, root] = header.x5c.slice(0, 3).map((c: string) => parseCert(b64ToBytes(c)));
  if ((await sha256Hex(root.der)) !== APPLE_ROOT_G3_SHA256) throw new Error("根证书不是 Apple Root CA - G3");
  if (!contains(leaf.der, OID_LEAF) || !contains(intermediate.der, OID_INTERMEDIATE)) throw new Error("证书用途不符");
  if (!(await verifyCertSignature(intermediate, root))) throw new Error("中间证书签名无效");
  if (!(await verifyCertSignature(leaf, intermediate))) throw new Error("叶证书签名无效");

  const key = await importKey(leaf);
  const ok = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    b64ToBytes(parts[2]),
    new TextEncoder().encode(`${parts[0]}.${parts[1]}`),
  );
  if (!ok) throw new Error("JWS 签名无效");
  return JSON.parse(new TextDecoder().decode(b64ToBytes(parts[1])));
}
