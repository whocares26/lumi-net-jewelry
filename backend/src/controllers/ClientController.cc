#include "ClientController.h"
#include <drogon/drogon.h>
using namespace drogon;
static HttpResponsePtr cors(HttpResponsePtr r){r->addHeader("Access-Control-Allow-Origin","*");return r;}
static HttpResponsePtr jsonErr(const std::string& m,HttpStatusCode c=k400BadRequest){
    Json::Value j;j["error"]=m;auto r=HttpResponse::newHttpJsonResponse(j);r->setStatusCode(c);return cors(r);}

void ClientController::getAll(const HttpRequestPtr& req,
    std::function<void(const HttpResponsePtr&)>&& cb){
    std::string srch   =req->getParameter("search");
    std::string storeId=req->getParameter("store_id");
    // Если передан store_id — клиенты только этого магазина
    if(!storeId.empty()){
        app().getDbClient()->execSqlAsync(
            "SELECT DISTINCT c.client_id,c.client_fio,c.client_phone,c.client_email "
            "FROM CLIENT c "
            "JOIN SALE s ON c.client_id=s.client_id "
            "WHERE s.store_id=$1::int "
            "  AND ($2='' OR lower(c.client_fio) LIKE lower('%'||$2||'%') "
            "       OR c.client_phone LIKE '%'||$2||'%') "
            "ORDER BY c.client_fio",
            [cb](const orm::Result& r){
                Json::Value arr(Json::arrayValue);
                for(const auto& row:r){Json::Value o;
                    o["id"]   =row["client_id"].as<int>();
                    o["fio"]  =row["client_fio"].isNull()?"":row["client_fio"].as<std::string>();
                    o["phone"]=row["client_phone"].as<std::string>();
                    o["email"]=row["client_email"].isNull()?"":row["client_email"].as<std::string>();
                    arr.append(o);}
                auto resp=HttpResponse::newHttpJsonResponse(arr);
                resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
            [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
            storeId,srch);
    } else {
        app().getDbClient()->execSqlAsync(
            "SELECT client_id,client_fio,client_phone,client_email FROM CLIENT "
            "WHERE $1='' OR lower(client_fio) LIKE lower('%'||$1||'%') "
            "   OR client_phone LIKE '%'||$1||'%' "
            "ORDER BY client_fio",
            [cb](const orm::Result& r){
                Json::Value arr(Json::arrayValue);
                for(const auto& row:r){Json::Value o;
                    o["id"]   =row["client_id"].as<int>();
                    o["fio"]  =row["client_fio"].isNull()?"":row["client_fio"].as<std::string>();
                    o["phone"]=row["client_phone"].as<std::string>();
                    o["email"]=row["client_email"].isNull()?"":row["client_email"].as<std::string>();
                    arr.append(o);}
                auto resp=HttpResponse::newHttpJsonResponse(arr);
                resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
            [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
            srch);
    }
}

void ClientController::getOne(const HttpRequestPtr&,
    std::function<void(const HttpResponsePtr&)>&& cb,int id){
    app().getDbClient()->execSqlAsync(
        "SELECT c.*,COUNT(s.sale_id) AS purchase_count,"
        "       COALESCE(SUM(s.sale_total),0) AS total_spent "
        "FROM CLIENT c LEFT JOIN SALE s ON c.client_id=s.client_id "
        "WHERE c.client_id=$1 GROUP BY c.client_id",
        [cb](const orm::Result& r){
            if(r.empty())return cb(jsonErr("Клиент не найден",k404NotFound));
            const auto row=r[0];Json::Value o;
            o["id"]            =row["client_id"].as<int>();
            o["fio"]           =row["client_fio"].isNull()?"":row["client_fio"].as<std::string>();
            o["phone"]         =row["client_phone"].as<std::string>();
            o["email"]         =row["client_email"].isNull()?"":row["client_email"].as<std::string>();
            o["purchase_count"]=row["purchase_count"].as<int>();
            o["total_spent"]   =row["total_spent"].as<double>();
            auto resp=HttpResponse::newHttpJsonResponse(o);
            resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},id);
}

void ClientController::update(const HttpRequestPtr& req,
    std::function<void(const HttpResponsePtr&)>&& cb,int id){
    auto b=req->getJsonObject();if(!b)return cb(jsonErr("JSON required"));
    std::string fio  =(*b)["fio"].asString();
    std::string phone=(*b)["phone"].asString();
    std::string email=(*b).get("email","").asString();
    app().getDbClient()->execSqlAsync(
        "UPDATE CLIENT SET client_fio=$1,client_phone=$2,client_email=NULLIF($3,'') WHERE client_id=$4",
        [cb](const orm::Result&){Json::Value o;o["ok"]=true;
            auto r=HttpResponse::newHttpJsonResponse(o);
            r->addHeader("Access-Control-Allow-Origin","*");cb(r);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
        fio,phone,email,id);
}
