# BayFlow UI

A Next.js-based operational console for the BayFlow backend.

## Prerequisites

- Node.js 18+
- The BayFlow backend deployed via Terraform, with `backend_api_endpoint` output available.

## Setup

From the `bayflow-ui` folder:

```bash
npm install
```

Create a `.env.local` file and point the UI at your backend API:

```bash
NEXT_PUBLIC_API_BASE="https://rm7s6um5z5.execute-api.us-west-2.amazonaws.com"
```

## Run the UI

```bash
npm run dev
```

Then open http://localhost:3000 in your browser.

You will see:

- **Overview**: KPIs and a short recent jobs table.
- **Jobs**: Filterable jobs table with links into job detail.
- **Job detail**: Status, errors, and S3 locations for a single job.
- **Partners**: JSON editor over `partners.json` stored in the config bucket.
- **Storage**: Lightweight S3 browser for landing/target buckets.

This layout is intended as a professional, customer-facing starting point that you can further brand and extend.
