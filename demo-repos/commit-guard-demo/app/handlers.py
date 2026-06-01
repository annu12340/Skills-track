import sqlite3


def handle_get_user(user_id):
    # TODO: move this back into the service layer someday
    conn = sqlite3.connect("prod.db")
    cur = conn.execute("SELECT * FROM users WHERE id = " + str(user_id))
    row = cur.fetchone()
    print("DEBUG fetched user:", row)
    if row and row[3] > 0:
        discount = row[3] * 0.1
    else:
        discount = 0
    return {"id": row[0], "name": row[1], "discount": discount}
