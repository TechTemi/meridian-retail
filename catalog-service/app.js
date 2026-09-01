/**
 * Meridian Retail Group — catalog-service
 * Express + node-postgres service serving the product catalog.
 *
 * This service is PRE-BUILT for the assessment. Do not modify application
 * logic — your job is the infrastructure around it, not the app code.
 *
 * Endpoints:
 *   GET /healthz              -> liveness check used by Nginx/monitoring
 *   GET /api/catalog/products -> list all products (seeds itself on boot)
 *   GET /api/catalog/products/:id -> fetch a single product
 */

const express = require("express");
const { Pool } = require("pg");

const app = express();
app.use(express.json());

const pool = new Pool({
  host: process.env.DB_HOST || "postgres",
  port: process.env.DB_PORT || 5432,
  database: process.env.DB_NAME || "meridian_db",
  user: process.env.DB_USER || "meridian",
  password: process.env.DB_PASSWORD || "meridian",
});

const SEED_PRODUCTS = [
  { name: "Adire Wrap Dress", price: 45.0, category: "Womenswear" },
  { name: "Aso-Oke Woven Tote", price: 32.5, category: "Accessories" },
  { name: "Kente Trim Blazer", price: 89.0, category: "Menswear" },
  { name: "Beaded Coral Necklace", price: 21.0, category: "Jewellery" },
  { name: "Ankara Print Sneakers", price: 58.0, category: "Footwear" },
];

async function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function initDb() {
  for (let attempt = 0; attempt < 10; attempt++) {
    try {
      await pool.query(`
        CREATE TABLE IF NOT EXISTS products (
          id SERIAL PRIMARY KEY,
          name TEXT NOT NULL,
          price NUMERIC(10, 2) NOT NULL,
          category TEXT NOT NULL,
          created_at TIMESTAMPTZ DEFAULT now()
        );
      `);

      const { rows } = await pool.query("SELECT COUNT(*) FROM products");
      if (parseInt(rows[0].count, 10) === 0) {
        for (const p of SEED_PRODUCTS) {
          await pool.query(
            "INSERT INTO products (name, price, category) VALUES ($1, $2, $3)",
            [p.name, p.price, p.category]
          );
        }
        console.log(`Seeded ${SEED_PRODUCTS.length} products`);
      }
      return;
    } catch (err) {
      console.log(`DB not ready (attempt ${attempt + 1}/10): ${err.message}`);
      await sleep(2000);
    }
  }
  throw new Error("Could not connect to database after retries");
}

app.get("/healthz", (req, res) => {
  res.json({ status: "ok", service: "catalog-service" });
});

app.get("/api/catalog/products", async (req, res) => {
  try {
    const { rows } = await pool.query("SELECT * FROM products ORDER BY id");
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: "Failed to fetch products" });
  }
});

app.get("/api/catalog/products/:id", async (req, res) => {
  try {
    const { rows } = await pool.query("SELECT * FROM products WHERE id = $1", [
      req.params.id,
    ]);
    if (rows.length === 0) {
      return res.status(404).json({ error: "Product not found" });
    }
    res.json(rows[0]);
  } catch (err) {
    res.status(500).json({ error: "Failed to fetch product" });
  }
});

const PORT = process.env.PORT || 4000;

initDb()
  .then(() => {
    app.listen(PORT, () => console.log(`catalog-service listening on ${PORT}`));
  })
  .catch((err) => {
    console.error("Fatal: could not initialise database", err);
    process.exit(1);
  });

module.exports = app;
