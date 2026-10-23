# PG Management System — API Contract (Phase 1)

This specification is the official integration contract for the **Flutter Frontend Developer** building:
1. **Admin Web Panel** (`client_type: "admin_web"`)
2. **Admin Android App** (`client_type: "admin_mobile"`)
3. **Resident Android App** (`client_type: "resident_mobile"`)

---

## 1. Base URL & Environments

- **Development Local**: `http://localhost:8000/api/v1`
- **Android Emulator**: `http://10.0.2.2:8000/api/v1`
- **Interactive Swagger Docs**: `http://localhost:8000/api/v1/docs`
- **ReDoc Documentation**: `http://localhost:8000/api/v1/redoc`

---

## 2. Standard Response & Error Envelope

All API endpoints return JSON conforming to the standard response envelope.

### Successful Response Format (`200 OK`, `201 Created`)
```json
{
  "success": true,
  "message": "Operation successful",
  "data": { ... },
  "timestamp": "2026-10-23T09:15:00.000000Z"
}
```

### Error Response Format (`400`, `401`, `403`, `404`, `409`, `422`, `500`)
```json
{
  "success": false,
  "error": {
    "code": "AUTHENTICATION_FAILED",
    "message": "Invalid email/phone or password.",
    "details": null
  },
  "timestamp": "2026-10-23T09:15:00.000000Z"
}
```

Common Error Codes:
- `AUTHENTICATION_FAILED` (`401`): Bad credentials, token expired or revoked.
- `PERMISSION_DENIED` (`403`): User lacks required role, wrong client type, or property not assigned.
- `NOT_FOUND` (`404`): Resource does not exist.
- `CONFLICT` (`409`): Unique constraint violation (e.g. email/phone already registered).
- `VALIDATION_ERROR` (`422`): Missing or invalid payload parameters.
- `INTERNAL_SERVER_ERROR` (`500`): Unexpected backend exception.

---

## 3. Client Isolation & Role Enforcement Rules

| Role Name | Admin Web (`admin_web`) | Admin Android (`admin_mobile`) | Resident Android (`resident_mobile`) | Property Scope |
| :--- | :---: | :---: | :---: | :--- |
| **`SUPER_ADMIN`** | Allowed | Allowed | Blocked (`403`) | All 5–6 properties in company portfolio |
| **`PROPERTY_MANAGER`**| Allowed | Allowed | Blocked (`403`) | Only assigned properties in `user_property_access` |
| **`STAFF`** | Allowed | Allowed | Blocked (`403`) | Only assigned properties in `user_property_access` |
| **`RESIDENT`** | Blocked (`403`) | Blocked (`403`) | Allowed | Strictly isolated to own room/bed/dues |

---

## 4. Test Accounts Seeded in Database

| Role | Identifier (Email / Phone) | Password | Allowed Client Types | Assigned Properties |
| :--- | :--- | :--- | :--- | :--- |
| **Super Admin** | `admin@originpg.com` / `9876543210` | `Admin@123456` | `admin_web`, `admin_mobile` | All 5 Properties |
| **Property Manager** | `manager@originpg.com` / `9876543211` | `Manager@123456` | `admin_web`, `admin_mobile` | Koramangala, HSR Layout |
| **Staff / Warden** | `staff@originpg.com` / `9876543212` | `Staff@123456` | `admin_web`, `admin_mobile` | Koramangala |
| **Resident** | `resident@originpg.com` / `9876543213` | `Resident@123456` | `resident_mobile` ONLY | Koramangala |

---

## 5. Endpoints Reference

### 5.1 Authentication Endpoints

#### `POST /auth/login`
Authenticates a user and returns JWT access and refresh tokens.

- **Request Body**:
```json
{
  "identifier": "admin@originpg.com",
  "password": "Admin@123456",
  "client_type": "admin_web",
  "device_info": "Chrome 122 on Windows 11"
}
```
*Note: `client_type` must be one of `admin_web`, `admin_mobile`, `resident_mobile`.*

- **Response `200 OK`**:
```json
{
  "success": true,
  "message": "Authenticated successfully as Super Administrator / Owner.",
  "data": {
    "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "token_type": "bearer",
    "expires_in": 3600,
    "user": {
      "id": "58fbd0eb-5d21-4bef-bc3d-6d787e3710ef",
      "company_id": "3490d8c9-74f9-4d4c-b5bb-5d19e14db06d",
      "full_name": "Rajesh Kumar (Owner)",
      "email": "admin@originpg.com",
      "phone": "9876543210",
      "role": {
        "id": "0522e548-f657-4184-925d-ed62145a149a",
        "name": "SUPER_ADMIN",
        "display_name": "Super Administrator / Owner",
        "description": "Full access to all properties...",
        "permissions": ["*"],
        "is_system_role": true
      },
      "allowed_properties": [
        {
          "id": "84ef8ffb-4877-443e-aad4-b79d8192a44e",
          "name": "Origin Grand PG - Koramangala",
          "code": "OG-KOR",
          "property_type": "CO_LIVING",
          "city": "Bangalore",
          "is_active": true
        }
      ],
      "is_active": true,
      "is_verified": true,
      "avatar_url": null,
      "last_login_at": "2026-10-23T09:12:34.000Z",
      "created_at": "2026-10-23T09:08:14.000Z"
    }
  },
  "timestamp": "2026-10-23T09:12:34.000Z"
}
```

---

#### `POST /auth/refresh`
Refreshes an expired access token using the stored refresh token.

- **Request Body**:
```json
{
  "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "client_type": "admin_web"
}
```
- **Response `200 OK`**: Returns refreshed `access_token` and current `user` profile.

---

#### `POST /auth/logout`
Revokes the refresh token and terminates the user's active session.

- **Headers**: `Authorization: Bearer <access_token>`
- **Request Body**:
```json
{
  "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

---

#### `GET /auth/me`
Retrieves current user profile and authorized properties.

- **Headers**: `Authorization: Bearer <access_token>`
- **Response `200 OK`**: Returns `UserProfile`.

---

#### `POST /auth/change-password`
Changes user password and invalidates all active refresh tokens across devices.

- **Headers**: `Authorization: Bearer <access_token>`
- **Request Body**:
```json
{
  "current_password": "Admin@123456",
  "new_password": "NewSecurePassword@2026"
}
```

---

### 5.2 Properties & Property Scoping Endpoints

#### `GET /properties`
Returns list of PG properties accessible to the authenticated user.
- **Headers**: `Authorization: Bearer <access_token>`
- **Response `200 OK`**: List of `PropertySummary`.

#### `GET /properties/{property_id}`
Returns full details of a specific PG property.
- **Headers**: `Authorization: Bearer <access_token>`
- **Response**: `200 OK` if authorized; `403 FORBIDDEN` if manager/staff lacks access.

#### `POST /properties`
Creates a new PG property. (*Super Admin Only*)
- **Headers**: `Authorization: Bearer <access_token>`
- **Request Body**:
```json
{
  "name": "Origin Prime PG - Bellandur",
  "code": "OG-BLR",
  "property_type": "MENS_PG",
  "address_line1": "89, Green Glen Layout, Bellandur",
  "city": "Bangalore",
  "state": "Karnataka",
  "pincode": "560103",
  "contact_phone": "+919876543205",
  "total_floors": 4,
  "is_active": true,
  "settings": {}
}
```

---

### 5.3 Users & Access Control Endpoints

#### `GET /users`
Lists users in the company. Supports pagination and filters.
- **Headers**: `Authorization: Bearer <access_token>`
- **Query Params**:
  - `role_name`: `SUPER_ADMIN`, `PROPERTY_MANAGER`, `STAFF`, `RESIDENT` (optional)
  - `is_active`: `true` / `false` (optional)
  - `page`: default `1`
  - `page_size`: default `20`

#### `GET /users/{user_id}`
Retrieves detailed profile of a specific user.

#### `POST /users`
Creates a new manager, staff, or resident.
- **Headers**: `Authorization: Bearer <access_token>`
- **Request Body**:
```json
{
  "full_name": "Suresh Nair",
  "email": "manager@originpg.com",
  "phone": "9876543211",
  "password": "Manager@123456",
  "role_id": "<role-uuid>",
  "property_ids": ["<property-uuid-1>", "<property-uuid-2>"]
}
```

#### `POST /users/{user_id}/assign-properties`
Assigns or updates property assignments for a manager or staff user. (*Super Admin Only*)
- **Headers**: `Authorization: Bearer <access_token>`
- **Request Body**:
```json
{
  "property_ids": ["<property-uuid-1>"],
  "access_level": "MANAGER"
}
```

---

### 5.4 Audit Trail Endpoints

#### `GET /audit-logs`
Returns audit records for all authentication and security events. (*Super Admin Only*)
- **Headers**: `Authorization: Bearer <access_token>`
- **Query Params**: `action`, `resource_type`, `property_id`, `page`, `page_size`
