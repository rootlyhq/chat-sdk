# Discord Adapter

The Discord adapter (`chat_sdk-discord`) handles Discord interactions and fetches message history through the REST API. It does not run a Gateway connection.

Use `application_id` or `bot_user_id` to identify the bot for mention metadata. Fetched messages set `message.is_mention` according to whether their `mentions` array contains that ID. `DISCORD_BOT_USER_ID` can be used when the bot user ID differs from the application ID.
