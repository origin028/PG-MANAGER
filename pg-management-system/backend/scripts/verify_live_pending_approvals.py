import urllib.request
import json
import secrets

def main():
    unique = secrets.token_hex(4)
    email = f"verify_approval_{unique}@originpg.com"
    pwd = "AdminPass@2026!"
    super_key = "ORG-240-X7K9-PQ82"

    print(f"1. Registering test admin: {email} with Super Key...")
    reg_payload = json.dumps({
        "business_name": f"Origin Test PG {unique}",
        "email": email,
        "password": pwd,
        "confirm_password": pwd,
        "super_key": super_key,
    }).encode("utf-8")

    req_reg = urllib.request.Request(
        "https://pg-management-api-sw09.onrender.com/api/v1/auth/admin/register",
        data=reg_payload,
        headers={"Content-Type": "application/json"}
    )
    try:
        with urllib.request.urlopen(req_reg, timeout=60) as resp:
            reg_res = json.loads(resp.read().decode("utf-8"))
            print("Admin registration response:", reg_res.get("message"))
    except urllib.error.HTTPError as e:
        print(f"Registration error {e.code}: {e.read().decode('utf-8')}")
        return
    except Exception as e:
        print("Registration failed:", e)
        return

    print("2. Logging in as registered admin...")
    login_payload = json.dumps({"email": email, "password": pwd}).encode("utf-8")
    req_login = urllib.request.Request(
        "https://pg-management-api-sw09.onrender.com/api/v1/auth/admin/login",
        data=login_payload,
        headers={"Content-Type": "application/json"}
    )
    try:
        with urllib.request.urlopen(req_login, timeout=60) as resp_l:
            login_res = json.loads(resp_l.read().decode("utf-8"))
            token = login_res["data"]["access_token"]
            user = login_res["data"]["user"]
            print(f"Logged in successfully as {user['email']} (Role: {user['role']}, Company: {user.get('company_id')})")

        print("3. Querying GET /api/v1/properties...")
        req_props = urllib.request.Request(
            "https://pg-management-api-sw09.onrender.com/api/v1/properties",
            headers={"Authorization": f"Bearer {token}"}
        )
        with urllib.request.urlopen(req_props, timeout=30) as resp_p:
            props_data = json.loads(resp_p.read().decode("utf-8")).get("data", [])
            print(f"Retrieved {len(props_data)} accessible properties:")
            for p in props_data:
                print(f" - {p['name']} ({p.get('code')})")

        print("\n4. Querying GET /api/v1/residents/pending-approvals...")
        req_appv = urllib.request.Request(
            "https://pg-management-api-sw09.onrender.com/api/v1/residents/pending-approvals",
            headers={"Authorization": f"Bearer {token}"}
        )
        with urllib.request.urlopen(req_appv, timeout=60) as resp_a:
            appv_res = json.loads(resp_a.read().decode("utf-8"))
            print("Pending approvals query success:", appv_res.get("success"))
            print("Total pending approvals:", appv_res["data"]["total"])
            print("Items count:", len(appv_res["data"]["items"]))
            for item in appv_res["data"]["items"]:
                print(f" - [{item['status']}] {item['full_name']} | Phone: {item['phone']} | Email: {item['email']} | Property: {item['property_name']}")

        if props_data:
            first_p = props_data[0]
            print(f"\n5. Verifying property access for '{first_p['name']}' ({first_p['id']})...")
            req_single = urllib.request.Request(
                f"https://pg-management-api-sw09.onrender.com/api/v1/properties/{first_p['id']}",
                headers={"Authorization": f"Bearer {token}"}
            )
            with urllib.request.urlopen(req_single, timeout=30) as resp_s:
                single_res = json.loads(resp_s.read().decode("utf-8"))
                print(f"Property access verified! Success: {single_res.get('success')}, Name: {single_res['data']['name']}")
    except urllib.error.HTTPError as e:
        print(f"Error {e.code}: {e.read().decode('utf-8')}")
    except Exception as e:
        print("Error during live verification:", e)

if __name__ == "__main__":
    main()
