# Privacy policy

TickTick for Garmin lets you read and update your TickTick data from a compatible Garmin watch. The service handles only the data needed to pair the watch and perform the operation you request.

## Data the service handles

During pairing, the service creates a short user code and a random device secret. It stores a hash of the device secret, the OAuth state, and the time the attempt expires. A pairing attempt expires after ten minutes.

After you approve TickTick access, the service stores your TickTick access token encrypted at rest. It stores the watch's relay token only as a one-way hash. These records stay until you unpair the watch or the credentials stop working.

Task titles, notes, dates, project identifiers, habits, and focus data may pass through the relay when you ask for them. The relay does not persist that content in its database. The watch keeps a small local task cache in its own Connect IQ application storage so it can remain useful without a connection.

For safe retries, the relay stores a random mutation identifier and its result for as long as the watch remains paired. This prevents a delayed watch retry from applying the same change twice. It does not store the task content with that record.

## Retention and deletion

Expired pairing attempts are removed automatically. When you unpair, the relay session is revoked immediately. Its encrypted TickTick token and mutation identifiers are removed by the next daily cleanup, within 24 hours. Removing the app from the watch also removes its local application storage under Garmin's normal device behavior.

## Sharing

The service sends requests to TickTick only to complete the task operation you requested. Cloudflare processes relay traffic and hosts the encrypted database. Garmin Connect carries network traffic between the watch and the internet when the watch uses the phone connection.

The service has no advertising, analytics, sale of personal data, or access to Garmin health, location, activity, payment, or contact data.

## Security

Network requests use HTTPS. On the relay, TickTick access tokens are encrypted at rest, and watch relay tokens and device secrets are stored only as hashes. The watch stores the pending device secret and active relay token in its private Connect IQ application storage because it needs them to finish pairing and authenticate requests. Unpairing or removing the app clears those local credentials. No system can promise perfect security, so the service keeps its data surface deliberately small.

## Your choices

You can revoke access from TickTick and unpair the watch at any time. For support or a data-deletion request, open a private-content-free issue through the [support page](support.md).

This project is independent and is not affiliated with TickTick, Garmin, or Cloudflare.
