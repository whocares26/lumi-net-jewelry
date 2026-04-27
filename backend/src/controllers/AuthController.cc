#include "AuthController.h"
#include "utils/JwtUtils.h"
#include <drogon/drogon.h>
#include <openssl/evp.h>
#include <sstream>
#include <iomanip>

using namespace drogon;

// SHA256 hex helper
static std::string sha256hex(const std::string& s) {
    unsigned char hash[EVP_MAX_MD_SIZE];
    unsigned int len = 0;
    EVP_MD_CTX* ctx = EVP_MD_CTX_new();
    EVP_DigestInit_ex(ctx, EVP_sha256(), nullptr);
    EVP_DigestUpdate(ctx, s.data(), s.size());
    EVP_DigestFinal_ex(ctx, hash, &len);
    EVP_MD_CTX_free(ctx);
    std::ostringstream oss;
    for (unsigned int i = 0; i < len; i++)
        oss << std::hex << std::setw(2) << std::setfill('0') << (int)hash[i];
    return oss.str();
}

static HttpResponsePtr cors(HttpResponsePtr r) {
    r->addHeader("Access-Control-Allow-Origin","*");
    return r;
}
static HttpResponsePtr jsonErr(const std::string& msg, HttpStatusCode code = k400BadRequest) {
    Json::Value j; j["error"] = msg;
    auto r = HttpResponse::newHttpJsonResponse(j); r->setStatusCode(code);
    return cors(r);
}

void AuthController::login(const HttpRequestPtr& req,
                            std::function<void(const HttpResponsePtr&)>&& cb) {
    auto body = req->getJsonObject();
    if (!body || !(*body)["username"] || !(*body)["password"])
        return cb(jsonErr("username и password обязательны"));

    std::string username = (*body)["username"].asString();
    std::string passHash = sha256hex((*body)["password"].asString());

    auto db = app().getDbClient();
    db->execSqlAsync(
        "SELECT user_id, role, ref_snils, ref_client_id FROM app_users "
        "WHERE username=$1 AND password_hash=$2",
        [cb, username](const orm::Result& r) {
            if (r.empty()) return cb(jsonErr("Неверный логин или пароль", k401Unauthorized));
            int uid = r[0]["user_id"].as<int>();
            std::string role = r[0]["role"].as<std::string>();
            std::string ref;
            if (!r[0]["ref_snils"].isNull())
                ref = r[0]["ref_snils"].as<std::string>();
            else if (!r[0]["ref_client_id"].isNull())
                ref = std::to_string(r[0]["ref_client_id"].as<int>());
            std::string token = JwtUtils::createToken(uid, role, ref);
            Json::Value resp;
            resp["token"] = token;
            resp["role"]  = role;
            resp["ref"]   = ref;
            resp["user_id"] = uid;
            auto hr = HttpResponse::newHttpJsonResponse(resp);
            hr->addHeader("Access-Control-Allow-Origin","*");
            cb(hr);
        },
        [cb](const orm::DrogonDbException& e) {
            cb(jsonErr(e.base().what(), k500InternalServerError));
        },
        username, passHash
    );
}

void AuthController::regist(const HttpRequestPtr& req,
                              std::function<void(const HttpResponsePtr&)>&& cb) {
    auto body = req->getJsonObject();
    if (!body) return cb(jsonErr("Требуется JSON тело"));
    std::string username = (*body).get("username","").asString();
    std::string password = (*body).get("password","").asString();
    std::string fio      = (*body).get("fio","").asString();
    std::string phone    = (*body).get("phone","").asString();
    std::string email    = (*body).get("email","").asString();
    if (username.empty() || password.empty() || fio.empty() || phone.empty())
        return cb(jsonErr("Обязательные поля: username, password, fio, phone"));

    std::string passHash = sha256hex(password);
    auto db = app().getDbClient();

    // Insert client first, then app_user
    db->execSqlAsync(
        "INSERT INTO CLIENT (client_phone,client_email,client_fio) VALUES($1,$2,$3) RETURNING client_id",
        [cb, username, passHash, email](const orm::Result& r) {
            int clientId = r[0]["client_id"].as<int>();
            auto db2 = app().getDbClient();
            db2->execSqlAsync(
                "INSERT INTO app_users (username,password_hash,role,ref_client_id) "
                "VALUES($1,$2,'CLIENT',$3) RETURNING user_id",
                [cb, clientId](const orm::Result& r2) {
                    int uid = r2[0]["user_id"].as<int>();
                    std::string token = JwtUtils::createToken(uid, "CLIENT", std::to_string(clientId));
                    Json::Value resp;
                    resp["token"]     = token;
                    resp["role"]      = "CLIENT";
                    resp["user_id"]   = uid;
                    resp["client_id"] = clientId;
                    auto hr = HttpResponse::newHttpJsonResponse(resp);
                    hr->setStatusCode(k201Created);
                    hr->addHeader("Access-Control-Allow-Origin","*");
                    cb(hr);
                },
                [cb](const orm::DrogonDbException& e) { cb(jsonErr(e.base().what(),k500InternalServerError)); },
                username, passHash, clientId
            );
        },
        [cb](const orm::DrogonDbException& e) { cb(jsonErr(e.base().what(),k500InternalServerError)); },
        phone, email.empty() ? "NULL" : email, fio
    );
}

void AuthController::me(const HttpRequestPtr& req,
                         std::function<void(const HttpResponsePtr&)>&& cb) {
    std::string authHeader = req->getHeader("Authorization");
    if (authHeader.size() < 8) return cb(jsonErr("Нет токена", k401Unauthorized));
    std::string token = authHeader.substr(7); // "Bearer "
    int uid; std::string role, ref;
    if (!JwtUtils::verifyToken(token, uid, role, ref))
        return cb(jsonErr("Недействительный токен", k401Unauthorized));

    Json::Value resp;
    resp["user_id"] = uid;
    resp["role"]    = role;
    resp["ref"]     = ref;
    auto r = HttpResponse::newHttpJsonResponse(resp);
    r->addHeader("Access-Control-Allow-Origin","*");
    cb(r);
}
