#include "ReviewController.h"
#include <drogon/drogon.h>
using namespace drogon;
static HttpResponsePtr cors(HttpResponsePtr r){r->addHeader("Access-Control-Allow-Origin","*");return r;}
static HttpResponsePtr jsonErr(const std::string& m,HttpStatusCode c=k400BadRequest){
    Json::Value j;j["error"]=m;auto r=HttpResponse::newHttpJsonResponse(j);r->setStatusCode(c);return cors(r);}

void ReviewController::getAll(const HttpRequestPtr&,
    std::function<void(const HttpResponsePtr&)>&& cb){
    app().getDbClient()->execSqlAsync(
        // Берём магазин: сначала явно указанный в отзыве,
        // иначе — последняя продажа клиента
        "SELECT r.review_id, r.review_rating, r.review_comment, r.review_date,"
        "       c.client_fio,"
        "       COALESCE("
        "         (SELECT st1.store_address FROM STORE st1 WHERE st1.store_id=r.store_id),"
        "         (SELECT st2.store_address FROM SALE sa "
        "          JOIN STORE st2 ON sa.store_id=st2.store_id "
        "          WHERE sa.client_id=r.client_id "
        "          ORDER BY sa.sale_date DESC LIMIT 1)"
        "       ) AS store_address "
        "FROM REVIEW r "
        "JOIN CLIENT c ON r.client_id=c.client_id "
        "ORDER BY r.review_date DESC",
        [cb](const orm::Result& r){
            Json::Value arr(Json::arrayValue);
            for(const auto& row:r){Json::Value o;
                o["id"]      = row["review_id"].as<int>();
                o["rating"]  = row["review_rating"].as<int>();
                o["comment"] = row["review_comment"].isNull()
                               ?"":row["review_comment"].as<std::string>();
                o["date"]    = row["review_date"].isNull()
                               ?"":row["review_date"].as<std::string>();
                o["client"]  = row["client_fio"].isNull()
                               ?"":row["client_fio"].as<std::string>();
                o["store"]   = row["store_address"].isNull()
                               ?"Магазин не указан":row["store_address"].as<std::string>();
                arr.append(o);}
            auto resp=HttpResponse::newHttpJsonResponse(arr);
            resp->addHeader("Access-Control-Allow-Origin","*"); cb(resp);},
        [cb](const orm::DrogonDbException& e){
            cb(jsonErr(e.base().what(),k500InternalServerError));});
}

void ReviewController::create(const HttpRequestPtr& req,
    std::function<void(const HttpResponsePtr&)>&& cb){
    auto b=req->getJsonObject();
    if(!b) return cb(jsonErr("JSON required"));
    int   clientId = (*b)["client_id"].asInt();
    short rating   = static_cast<short>((*b)["rating"].asInt());
    std::string comment = (*b).get("comment","").asString();
    // store_id опциональный
    bool hasStore = (*b).isMember("store_id") && !(*b)["store_id"].isNull()
                    && (*b)["store_id"].asInt()>0;
    if(hasStore){
        int storeId=(*b)["store_id"].asInt();
        app().getDbClient()->execSqlAsync(
            "INSERT INTO REVIEW(client_id,review_rating,review_comment,review_date,store_id) "
            "VALUES($1,$2,$3,CURRENT_DATE,$4) RETURNING review_id",
            [cb](const orm::Result& r){
                Json::Value o; o["id"]=r[0]["review_id"].as<int>();
                auto resp=HttpResponse::newHttpJsonResponse(o);
                resp->setStatusCode(k201Created);
                resp->addHeader("Access-Control-Allow-Origin","*"); cb(resp);},
            [cb](const orm::DrogonDbException& e){
                cb(jsonErr(e.base().what(),k500InternalServerError));},
            clientId,rating,comment,storeId);
    } else {
        app().getDbClient()->execSqlAsync(
            "INSERT INTO REVIEW(client_id,review_rating,review_comment,review_date) "
            "VALUES($1,$2,$3,CURRENT_DATE) RETURNING review_id",
            [cb](const orm::Result& r){
                Json::Value o; o["id"]=r[0]["review_id"].as<int>();
                auto resp=HttpResponse::newHttpJsonResponse(o);
                resp->setStatusCode(k201Created);
                resp->addHeader("Access-Control-Allow-Origin","*"); cb(resp);},
            [cb](const orm::DrogonDbException& e){
                cb(jsonErr(e.base().what(),k500InternalServerError));},
            clientId,rating,comment);
    }
}

void ReviewController::remove(const HttpRequestPtr&,
    std::function<void(const HttpResponsePtr&)>&& cb,int id){
    app().getDbClient()->execSqlAsync("DELETE FROM REVIEW WHERE review_id=$1",
        [cb](const orm::Result&){
            Json::Value o; o["ok"]=true;
            auto r=HttpResponse::newHttpJsonResponse(o);
            r->addHeader("Access-Control-Allow-Origin","*"); cb(r);},
        [cb](const orm::DrogonDbException& e){
            cb(jsonErr(e.base().what(),k500InternalServerError));},id);
}
