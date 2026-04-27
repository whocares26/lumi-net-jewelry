#include "JwtUtils.h"
#include <openssl/hmac.h>
#include <openssl/evp.h>
#include <cstring>
#include <cstdlib>
#include <ctime>
#include <sstream>
#include <vector>

static const long TOKEN_TTL = 86400 * 7; // 7 days

// ── Base64URL helpers ──────────────────────────────────────────
static const char B64_CHARS[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

static std::string b64url_encode(const unsigned char* buf, size_t len) {
    std::string out;
    out.reserve(((len + 2) / 3) * 4);
    for (size_t i = 0; i < len; i += 3) {
        unsigned int v = (unsigned int)buf[i] << 16;
        if (i + 1 < len) v |= (unsigned int)buf[i+1] << 8;
        if (i + 2 < len) v |= (unsigned int)buf[i+2];
        out += B64_CHARS[(v >> 18) & 0x3F];
        out += B64_CHARS[(v >> 12) & 0x3F];
        out += (i + 1 < len) ? B64_CHARS[(v >> 6) & 0x3F] : '=';
        out += (i + 2 < len) ? B64_CHARS[(v)      & 0x3F] : '=';
    }
    for (auto& c : out) {
        if (c == '+') c = '-';
        else if (c == '/') c = '_';
    }
    // Remove padding
    while (!out.empty() && out.back() == '=') out.pop_back();
    return out;
}

static std::string b64url_decode(const std::string& in) {
    std::string s = in;
    for (auto& c : s) {
        if (c == '-') c = '+';
        else if (c == '_') c = '/';
    }
    while (s.size() % 4) s += '=';
    std::vector<unsigned char> out;
    int val = 0, bits = -8;
    for (unsigned char c : s) {
        if (c == '=') break;
        const char* p = strchr(B64_CHARS, c);
        if (!p) return {};
        val = (val << 6) + (int)(p - B64_CHARS);
        bits += 6;
        if (bits >= 0) {
            out.push_back((val >> bits) & 0xFF);
            bits -= 8;
        }
    }
    return std::string(out.begin(), out.end());
}

// ── HMAC-SHA256 ───────────────────────────────────────────────
static std::string hmac_sha256_b64(const std::string& key, const std::string& data) {
    unsigned char hash[EVP_MAX_MD_SIZE];
    unsigned int  len = 0;
    HMAC(EVP_sha256(),
         key.data(), (int)key.size(),
         (const unsigned char*)data.data(), data.size(),
         hash, &len);
    return b64url_encode(hash, len);
}

// ── Simple JSON helpers ───────────────────────────────────────
static std::string jsonStr(const std::string& k, const std::string& v) {
    return "\"" + k + "\":\"" + v + "\"";
}
static std::string jsonNum(const std::string& k, long v) {
    return "\"" + k + "\":" + std::to_string(v);
}

static std::string getJsonField(const std::string& json, const std::string& key) {
    // Find "key":"value"
    std::string pat = "\"" + key + "\":\"";
    auto pos = json.find(pat);
    if (pos == std::string::npos) {
        // Try numeric
        pat = "\"" + key + "\":";
        pos = json.find(pat);
        if (pos == std::string::npos) return {};
        pos += pat.size();
        auto end = json.find_first_of(",}", pos);
        return json.substr(pos, end - pos);
    }
    pos += pat.size();
    auto end = json.find('"', pos);
    return json.substr(pos, end - pos);
}

// ── Public API ────────────────────────────────────────────────
namespace JwtUtils {

std::string createToken(int userId, const std::string& role, const std::string& refId) {
    const char* secret = getenv("JWT_SECRET");
    std::string key = secret ? secret : "lumi_default_secret";

    // Header
    std::string headerJson = R"({"alg":"HS256","typ":"JWT"})";
    std::string header = b64url_encode(
        (const unsigned char*)headerJson.data(), headerJson.size());

    // Payload
    long now = (long)time(nullptr);
    std::string payloadJson = "{" +
        jsonNum("uid", userId) + "," +
        jsonStr("role", role) + "," +
        jsonStr("ref", refId) + "," +
        jsonNum("iat", now) + "," +
        jsonNum("exp", now + TOKEN_TTL) +
    "}";
    std::string payload = b64url_encode(
        (const unsigned char*)payloadJson.data(), payloadJson.size());

    std::string sig = hmac_sha256_b64(key, header + "." + payload);
    return header + "." + payload + "." + sig;
}

bool verifyToken(const std::string& token, int& uid, std::string& role, std::string& ref) {
    const char* secret = getenv("JWT_SECRET");
    std::string key = secret ? secret : "lumi_default_secret";

    auto dot1 = token.find('.');
    auto dot2 = token.rfind('.');
    if (dot1 == std::string::npos || dot2 == dot1) return false;

    std::string header  = token.substr(0, dot1);
    std::string payload = token.substr(dot1 + 1, dot2 - dot1 - 1);
    std::string sig     = token.substr(dot2 + 1);

    // Verify signature
    std::string expected = hmac_sha256_b64(key, header + "." + payload);
    if (expected != sig) return false;

    // Decode payload
    std::string json = b64url_decode(payload);
    if (json.empty()) return false;

    // Check expiry
    std::string expStr = getJsonField(json, "exp");
    if (expStr.empty()) return false;
    long exp = std::stol(expStr);
    if ((long)time(nullptr) > exp) return false;

    // Extract fields
    std::string uidStr = getJsonField(json, "uid");
    if (uidStr.empty()) return false;
    uid  = std::stoi(uidStr);
    role = getJsonField(json, "role");
    ref  = getJsonField(json, "ref");
    return true;
}

} // namespace JwtUtils
