/*==============================================================*/
/* DBMS name:	PostgreSQL 9.x	*/
/* Created on:	02.12.2025 20:37:12	*/
/*==============================================================*/
/*==============================================================*/
/* Table: CASHIER	*/
/*==============================================================*/
create table CASHIER (
cashier_snils		VARCHAR(14)		not null, manager_snils			CHAR(14)	not null, cashier_fio	VARCHAR(100)		 not null, constraint PK_CASHIER primary key (cashier_snils)
);
/*==============================================================*/
/* Index: CASHIER_PK	*/
/*==============================================================*/
create unique index CASHIER_PK on CASHIER ( cashier_snils
);
/*==============================================================*/
/* Index: APPOINTS_FK	*/
/*==============================================================*/
create index APPOINTS_FK on CASHIER ( manager_snils
);
/*==============================================================*/
/* Table: CLIENT	*/
/*==============================================================*/
create table CLIENT (
client_id	SERIAL	not null, client_phone			VARCHAR(20)		not null, client_email		VARCHAR(100)		 null, client_fio	 VARCHAR(100)		null, constraint PK_CLIENT primary key (client_id)
);

/*==============================================================*/
/* Index: CLIENT_PK	*/
/*==============================================================*/
 
create unique index CLIENT_PK on CLIENT ( client_id
);
/*==============================================================*/
/* Table: MANAGER	*/
/*==============================================================*/
create table MANAGER (
manager_snils		CHAR(14)	not null, manager_fio	VARCHAR(100)		not null, constraint PK_MANAGER primary key (manager_snils)
);
/*==============================================================*/
/* Index: MANAGER_PK	*/
/*==============================================================*/
create unique index MANAGER_PK on MANAGER ( manager_snils
);
/*==============================================================*/
/* Table: "ORDER"	*/
/*==============================================================*/
create table "ORDER" (
order_id		SERIAL		not null, store_id	INT4	not null,
supplier_id		INT4		not null, manager_snils				CHAR(14)				not null, order_date		 DATE			not null, order_status			VARCHAR(50)			not null, order_total	INT8	not null, constraint PK_ORDER primary key (order_id)
);

/*==============================================================*/
/* Index: ORDER_PK	*/
/*==============================================================*/
create unique index ORDER_PK on "ORDER" ( order_id
);

/*==============================================================*/
/* Index: DRIVES_FK	*/
/*==============================================================*/
create index DRIVES_FK on "ORDER" (
 
store_id
);

/*==============================================================*/
/* Index: DELIVERS_FK	*/
/*==============================================================*/
create index DELIVERS_FK on "ORDER" ( supplier_id
);
/*==============================================================*/
/* Index: ORDERS_FK	*/
/*==============================================================*/
create index ORDERS_FK on "ORDER" ( manager_snils
);
/*==============================================================*/
/* Table: ORDER_ITEM	*/
/*==============================================================*/
create table ORDER_ITEM (
order_id	INT4	not null, order_item_id		INT4		not null,
product_article	INT4	not null, order_item_quantity INT4		not null,
constraint PK_ORDER_ITEM primary key (order_id, order_item_id)
);

/*==============================================================*/
/* Index: ORDER_ITEM_PK	*/
/*==============================================================*/
create unique index ORDER_ITEM_PK on ORDER_ITEM ( order_id,
order_item_id
);
/*==============================================================*/
/* Index: ORDER_CONTAINS_PRODUCTS_FK	*/
/*==============================================================*/
create index ORDER_CONTAINS_PRODUCTS_FK on ORDER_ITEM ( order_id
);

/*==============================================================*/
 
/*==============================================================*/
create index CONTAINS_THE_PRODUCT_FK on ORDER_ITEM ( product_article
);
/*==============================================================*/
/* Table: PRODUCT	*/
/*==============================================================*/
create table PRODUCT (
product_article	 INT4	not null, product_category			VARCHAR(50)	 not null, product_price	INT4	 not null, product_name		VARCHAR(100)	not null, constraint PK_PRODUCT primary key (product_article)
);
/*==============================================================*/
/* Index: PRODUCT_PK	*/
/*==============================================================*/
create unique index PRODUCT_PK on PRODUCT ( product_article
);
/*==============================================================*/
/* Table: REVIEW	*/
/*==============================================================*/
create table REVIEW (
review_id		SERIAL			not null, client_id	INT4		not null, review_rating				INT2		not null, review_comment				VARCHAR(500)	null, review_date			DATE			 null, constraint PK_REVIEW primary key (review_id)
);

/*==============================================================*/
/* Index: REVIEW_PK	*/
/*==============================================================*/
create unique index REVIEW_PK on REVIEW ( review_id
);
/*==============================================================*/
/* Index: WRITES_FK	*/
/*==============================================================*/
 
create index WRITES_FK on REVIEW ( client_id
);
/*==============================================================*/
/* Table: SALE	*/
/*==============================================================*/
create table SALE (
sale_id	SERIAL	not null,
client_id	 INT4	 not null, cashier_snils			VARCHAR(14)		not null, store_id	INT4	not null, sale_total		FLOAT8		not null,
sale_payment_method VARCHAR(100)	not null, sale_date	DATE	not null,
constraint PK_SALE primary key (sale_id)
);
/*==============================================================*/
/* Index: SALE_PK	*/
/*==============================================================*/
create unique index SALE_PK on SALE ( sale_id
);
/*==============================================================*/
/* Index: BUYS_FK	*/
/*==============================================================*/
create index BUYS_FK on SALE ( client_id
);
/*==============================================================*/
/* Index: PROCESSES_FK	*/
/*==============================================================*/
create index PROCESSES_FK on SALE ( cashier_snils
);
/*==============================================================*/
/* Index: MAKES_FK	*/
/*==============================================================*/
create index MAKES_FK on SALE ( store_id
);
 
/*==============================================================*/
/* Table: SALE_ITEM	*/
/*==============================================================*/
create table SALE_ITEM (
sale_id	INT4	not null, sale_item_id		INT4		not null,
product_article	INT4	not null, sale_item_quantity		INT4		not null,
constraint PK_SALE_ITEM primary key (sale_id, sale_item_id)
);
/*==============================================================*/
/* Index: SALE_ITEM_PK	*/
/*==============================================================*/
create unique index SALE_ITEM_PK on SALE_ITEM ( sale_id,
sale_item_id
);
/*==============================================================*/
/* Index: SALE_INCLUDES_PRODUCTS_FK	*/
/*==============================================================*/
create index SALE_INCLUDES_PRODUCTS_FK on SALE_ITEM ( sale_id
);

/*==============================================================*/
/* Index: SALE_CONTAINS_PRODUCT_FK	*/
/*==============================================================*/
create index SALE_CONTAINS_PRODUCT_FK on SALE_ITEM ( product_article
);

/*==============================================================*/
/* Table: STOCK	*/
/*==============================================================*/
create table STOCK (
store_id	INT4	not null,
stock_id	INT4	not null, product_article		INT4		not null,
stock_quantity	INT4	not null,
constraint PK_STOCK primary key (store_id, stock_id)
);
 
/*==============================================================*/
/* Index: STOCK_PK	*/
/*==============================================================*/
create unique index STOCK_PK on STOCK ( store_id,
stock_id
);

/*==============================================================*/
/* Index: STORE_STORES_PRODUCTS_FK	*/
/*==============================================================*/
create index STORE_STORES_PRODUCTS_FK on STOCK ( store_id
);

/*==============================================================*/
/* Index: STORES_PRODUCT_FK	*/
/*==============================================================*/
create index STORES_PRODUCT_FK on STOCK ( product_article
);

/*==============================================================*/
/* Table: STORE	*/
/*==============================================================*/
create table STORE (
store_id	SERIAL	not null, manager_snils			CHAR(14)		null, store_address		 VARCHAR(100)			not null, store_phone		VARCHAR(20)		not null, constraint PK_STORE primary key (store_id)
);

/*==============================================================*/
/* Index: STORE_PK	*/
/*==============================================================*/
create unique index STORE_PK on STORE ( store_id
);

/*==============================================================*/
/* Index: MANAGES_FK	*/
/*==============================================================*/
create index MANAGES_FK on STORE ( manager_snils
 
);

/*==============================================================*/
/* Table: SUPPLIER	*/
/*==============================================================*/
create table SUPPLIER (
supplier_id	SERIAL	not null, supplier_name			VARCHAR(100)		not null, supplier_email		VARCHAR(255)	 not null, supplier_phone			 VARCHAR(20)	not null, constraint PK_SUPPLIER primary key (supplier_id)
);
/*==============================================================*/
/* Index: SUPPLIER_PK	*/
/*==============================================================*/
create unique index SUPPLIER_PK on SUPPLIER ( supplier_id
);
/*==============================================================*/
/* Index: idx_client_phone	*/
/*==============================================================*/
create index idx_client_phone on CLIENT (client_phone);
/*==============================================================*/
/* Index: idx_product_name	*/
/*==============================================================*/
create index idx_product_name on PRODUCT (product_name);
/*==============================================================*/
/* Index: idx_order_date	*/
/*==============================================================*/
create index idx_order_date on "ORDER" (order_date);


alter table CASHIER
add constraint FK_CASHIER_APPOINTS_MANAGER foreign key (manager_snils) references MANAGER (manager_snils)
on delete restrict on update restrict;

alter table "ORDER"
add constraint FK_ORDER_DELIVERS_SUPPLIER foreign key (supplier_id) references SUPPLIER (supplier_id)
on delete restrict on update restrict;
 
alter table "ORDER"
add constraint FK_ORDER_DRIVES_STORE foreign key (store_id) references STORE (store_id)
on delete restrict on update restrict;
alter table "ORDER"
add constraint FK_ORDER_ORDERS_MANAGER foreign key (manager_snils) references MANAGER (manager_snils)
on delete restrict on update restrict;
alter table ORDER_ITEM
add constraint FK_ORDER_IT_CONTAINS_PRODUCT foreign key (product_article) references PRODUCT (product_article)
on delete restrict on update restrict;

alter table ORDER_ITEM
add constraint FK_ORDER_IT_ORDER_CON_ORDER foreign key (order_id) references "ORDER" (order_id)
on delete cascade on update restrict;

alter table REVIEW
add constraint FK_REVIEW_WRITES_CLIENT foreign key (client_id) references CLIENT (client_id)
on delete restrict on update restrict;
alter table SALE
add constraint FK_SALE_BUYS_CLIENT foreign key (client_id) references CLIENT (client_id)
on delete restrict on update restrict;

alter table SALE
add constraint FK_SALE_MAKES_STORE foreign key (store_id) references STORE (store_id)
on delete restrict on update restrict;
alter table SALE
add constraint FK_SALE_PROCESSES_CASHIER foreign key (cashier_snils) references CASHIER (cashier_snils)
on delete restrict on update restrict;

alter table SALE_ITEM
add constraint FK_SALE_ITE_SALE_CONT_PRODUCT foreign key (product_article) references PRODUCT (product_article)
on delete restrict on update restrict;
 
alter table SALE_ITEM
add constraint FK_SALE_ITE_SALE_INCL_SALE foreign key (sale_id) references SALE (sale_id)
on delete cascade on update restrict;
alter table STOCK
add constraint FK_STOCK_STORES_PR_PRODUCT foreign key (product_article) references PRODUCT (product_article)
on delete restrict on update restrict;
alter table STOCK
add constraint FK_STOCK_STORE_STO_STORE foreign key (store_id) references STORE (store_id)
on delete cascade on update restrict;

alter table STORE
add constraint FK_STORE_MANAGES_MANAGER foreign key (manager_snils) references MANAGER (manager_snils)
on delete set null on update restrict;
