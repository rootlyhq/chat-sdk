import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
  static targets = ["messages", "input"]
  static values = { channel: { type: String, default: "default" } }

  connect() {
    this.userId = "guest-" + Math.random().toString(36).substr(2, 6)
    this.consumer = createConsumer()
    this.subscription = this.consumer.subscriptions.create(
      { channel: "ChatChannel", channel_id: this.channelValue },
      {
        received: (html) => {
          this.messagesTarget.insertAdjacentHTML("beforeend", html)
          this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
        }
      }
    )
  }

  disconnect() {
    this.subscription?.unsubscribe()
    this.consumer?.disconnect()
  }

  send(event) {
    event.preventDefault()
    const text = this.inputTarget.value.trim()
    if (!text) return

    this.subscription.send({
      message: text,
      user_id: this.userId,
      user_name: "Guest"
    })
    this.inputTarget.value = ""
  }
}
