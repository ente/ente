import React from "react";
import ReactDOM from "react-dom/client";
import { App } from "./App";
import "./styles/globals.css";

const root = document.getElementById("root");
if (!root) throw new Error("Could not load root element to render onto");

ReactDOM.createRoot(root).render(
    <React.StrictMode>
        <App />
    </React.StrictMode>,
);
