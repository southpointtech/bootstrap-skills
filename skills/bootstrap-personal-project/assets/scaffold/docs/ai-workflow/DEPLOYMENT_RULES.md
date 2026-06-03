# Deployment Rules

## General

Claude must never deploy without explicit human approval.

## Frontend / Hosting

Before deploying a frontend (Firebase Hosting, Azure Static Web Apps, or other):

- Confirm hosting target and environment.
- Confirm build configuration and environment variables.
- Run or define Playwright QA.

## Firebase Backend

Before Firebase deployment:

- Confirm Firebase project ID.
- Confirm Cloud Functions target.
- Confirm environment variables/secrets.
- Confirm Firestore rules and indexes impact.
- Confirm whether deployment is staging or production.
- Do not deploy without approval.

## Azure Backend

Before Azure deployment:

- Confirm Azure subscription/resource group.
- Confirm Functions/App Service target.
- Confirm environment variables/secrets.
- Confirm auth model.
- Confirm whether deployment is staging or production.
- Do not deploy without approval.
