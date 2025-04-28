import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import connectDB from './config/db.js';
import apiRoutes from './routes/api.js';
import path from "path";

dotenv.config();

const app = express();
const port = process.env.port || 5000;
const __dirname = path.resolve()

connectDB().then(r => {});

app.use(cors());
app.use(express.json());
app.use('/api', apiRoutes);
// Serve static files from client/dist
app.use(express.static(path.join(__dirname, '/client/dist')));

// Serve frontend for all other routes (SPA)
app.get('*', (req, res) => {
    res.sendFile(path.join(__dirname, 'client', 'dist', 'index.html'));
});

app.listen(port, () => {
    console.log(`Server running at http://localhost:${port}`)
});

export default app