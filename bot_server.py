import subprocess
import time
import requests

TOKEN = "8501073690:AAFi_dZa_wzmLYtNHa6GoptDGqqqdP7l3yY"
CHAT_ID = "8325156711"
API_URL = f"https://api.telegram.org/bot{TOKEN}"

def send_message(text):
    url = f"{API_URL}/sendMessage"
    data = {"chat_id": CHAT_ID, "text": text}
    requests.post(url, data=data)

def send_htop():
    try:
        output = subprocess.check_output(["ps", "aux"]).decode()
        # 원하는 keyword 필터링
        lines = [line for line in output.split("\n") if "scale.py" in line or "dram_sim.py" in line]
        if not lines:
            send_message("현재 실행 중인 실험 프로세스 없음.")
        else:
            send_message("```\n" + "\n".join(lines) + "\n```")
    except Exception as e:
        send_message(f"오류 발생: {e}")


def run_bot():
    offset = None
    send_message("텔레그램 봇이 caccini에서 실행되었습니다.")
    send_message("/htop 명령어를 보내면 현재 시스템 상태를 받을 수 있습니다.")


    while True:
        try:
            url = f"{API_URL}/getUpdates"
            if offset:
                url += f"?offset={offset}"

            updates = requests.get(url).json()

            if "result" in updates:
                for item in updates["result"]:
                    offset = item["update_id"] + 1
                    msg = item.get("message", {})
                    text = msg.get("text", "")

                    if text == "/htop":
                        send_htop()

            time.sleep(1)
        except Exception as e:
            print("Error:", e)
            time.sleep(3)

if __name__ == "__main__":
    run_bot()

## background
## nohup python3 bot_server.py > bot.log 2>&1 &
## ps aux | grep bot_server
## pkill -f bot_server.py

