@"

\# API Documentation



\## Base URL

\\`http://localhost:8080\\`



\## Orders API



\### List Orders

\\`GET /api/orders\\`



Response:

\\`\\`\\`json

\[

&#x20; {

&#x20;   "id": "uuid",

&#x20;   "customer\_id": "cust-123",

&#x20;   "items": \[...],

&#x20;   "total\_amount": "199.98",

&#x20;   "status": "pending",

&#x20;   "created\_at": "2026-08-21T01:45:41.783Z"

&#x20; }

]

\\`\\`\\`



\### Create Order

\\`POST /api/orders\\`



Request:

\\`\\`\\`json

{

&#x20; "customer\_id": "cust-123",

&#x20; "items": \[

&#x20;   {

&#x20;     "product\_id": "prod-id",

&#x20;     "quantity": 2,

&#x20;     "price": 99.99

&#x20;   }

&#x20; ],

&#x20; "total\_amount": 199.98

}

\\`\\`\\`



\## Inventory API



\### List Products

\\`GET /api/inventory\\`



\### Create Product

\\`POST /api/inventory\\`



Request:

\\`\\`\\`json

{

&#x20; "name": "Notebook Dell",

&#x20; "sku": "DELL-XPS-13",

&#x20; "quantity": 50,

&#x20; "price": 4999.99

}

\\`\\`\\`



\### Check Availability

\\`POST /api/inventory/check-availability\\`



Request:

\\`\\`\\`json

{

&#x20; "items": \[

&#x20;   {

&#x20;     "productId": "prod-id",

&#x20;     "quantity": 2

&#x20;   }

&#x20; ]

}

\\`\\`\\`



Response:

\\`\\`\\`json

{

&#x20; "available": true,

&#x20; "items": \[

&#x20;   {

&#x20;     "productId": "prod-id",

&#x20;     "available": true,

&#x20;     "currentQuantity": 50

&#x20;   }

&#x20; ]

}

\\`\\`\\`



\## Payments API



\### List Payments

\\`GET /api/payments\\`



\### Create Payment

\\`POST /api/payments\\`



Request:

\\`\\`\\`json

{

&#x20; "order\_id": "order-id",

&#x20; "amount": 199.98,

&#x20; "payment\_method": "credit\_card"

}

\\`\\`\\`

"@ | Out-File API.md -Encoding UTF8

