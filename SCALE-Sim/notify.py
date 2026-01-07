import argparse
import requests


TOKEN = "."
CHAT_ID = "8325156711"

def send_message(text):
    url = f"https://api.telegram.org/bot{TOKEN}/sendMessage"
    data = {"chat_id": CHAT_ID, "text": text}
    requests.post(url, data=data)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--msg", type=str, required=True)
    args = parser.parse_args()

    send_message(f"실험 완료: {args.msg}")
