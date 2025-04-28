import React from 'react'
import { ChakraProvider } from '@chakra-ui/react'
import App from './App'
import {BrowserRouter} from "react-router-dom"
import {createRoot} from "react-dom/client";
import {StrictMode} from "react";

createRoot(document.getElementById('root')).render(
    <StrictMode>
        <BrowserRouter>
            <ChakraProvider>
                <App />
            </ChakraProvider>
        </BrowserRouter>
    </StrictMode>,
)