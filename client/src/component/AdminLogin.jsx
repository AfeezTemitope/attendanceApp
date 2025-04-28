import React, { useState } from 'react';
import {
    Box,
    Heading,
    Button,
    Text,
    Input,
    FormControl,
    FormLabel,
    useToast,
    Stack,
    Flex,
    Spinner,
} from '@chakra-ui/react';
import { keyframes } from '@emotion/react';
import axios from 'axios';
import { useNavigate } from 'react-router-dom';
import { motion } from 'framer-motion';

// Custom animation for button bounce
const bounce = keyframes`
    0%, 100% { transform: translateY(0); }
    50% { transform: translateY(-5px); }
`;

// Custom toast styles
const toastStyles = {
    container: {
        borderRadius: '12px',
        bg: 'rgba(255, 255, 255, 0.9)',
        boxShadow: '0 4px 12px rgba(0, 0, 0, 0.1)',
        backdropFilter: 'blur(10px)',
    },
    title: {
        fontWeight: 'bold',
        color: '#4A5568',
    },
    description: {
        color: '#718096',
    },
};

const AdminLogin = () => {
    const [username, setUsername] = useState('');
    const [password, setPassword] = useState('');
    const [error, setError] = useState('');
    const [isLoading, setIsLoading] = useState(false);
    const toast = useToast();
    const navigate = useNavigate();

    const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

    const handleLogin = async () => {
        if (!username || !password) {
            setError('Username and password cannot be empty');
            toast({
                title: 'Error',
                description: 'Username and password cannot be empty.',
                status: 'error',
                duration: 3000,
                isClosable: true,
                containerStyle: toastStyles.container,
                titleStyle: toastStyles.title,
                descriptionStyle: toastStyles.description,
            });
            return;
        }

        setIsLoading(true);

        try {
            const serverRequest = axios.post('/api/admin/login', { username, password });
            const [res] = await Promise.all([serverRequest, delay(2000)]);
            console.log('Login response:', res.data); // Debug log
            if (res.data.success && res.data.data.token) {
                localStorage.setItem('adminToken', res.data.data.token);
                console.log('Token stored:', localStorage.getItem('adminToken')); // Debug log
                toast({
                    title: 'Login Successful',
                    description: 'You have successfully logged in.',
                    status: 'success',
                    duration: 3000,
                    isClosable: true,
                    containerStyle: toastStyles.container,
                    titleStyle: toastStyles.title,
                    descriptionStyle: toastStyles.description,
                });
                navigate('/attendance');
            } else {
                setError('Login failed: Invalid response from server');
                toast({
                    title: 'Error',
                    description: 'Invalid response from the server.',
                    status: 'error',
                    duration: 3000,
                    isClosable: true,
                    containerStyle: toastStyles.container,
                    titleStyle: toastStyles.title,
                    descriptionStyle: toastStyles.description,
                });
            }
        } catch (err) {
            const errorMessage = err.response?.data?.message || 'Login failed';
            setError(errorMessage);
            toast({
                title: 'Error',
                description: errorMessage,
                status: 'error',
                duration: 3000,
                isClosable: true,
                containerStyle: toastStyles.container,
                titleStyle: toastStyles.title,
                descriptionStyle: toastStyles.description,
            });
        } finally {
            setIsLoading(false);
        }
    };

    return (
        <Flex
            align="center"
            justify="center"
            minHeight="100vh"
            bgGradient="linear(to-br, pink.200, purple.300, blue.200)"
            position="relative"
            overflow="hidden"
        >
            {/* Animated background wave */}
            <Box
                as="svg"
                position="absolute"
                bottom="0"
                left="0"
                width="100%"
                height="30%"
                viewBox="0 0 1440 320"
                preserveAspectRatio="none"
                opacity="0.3"
            >
                <path
                    fill="#ffffff"
                    fillOpacity="0.5"
                    d="M0,192L48,186.7C96,181,192,171,288,181.3C384,192,480,224,576,213.3C672,203,768,149,864,138.7C960,128,1056,160,1152,176C1248,192,1344,192,1392,192L1440,192L1440,320L1392,320C1344,320,1248,320,1152,320C1056,320,960,320,864,320C768,320,672,320,576,320C480,320,384,320,288,320C192,320,96,320,48,320L0,320Z"
                >
                    <animate
                        attributeName="d"
                        dur="10s"
                        repeatCount="indefinite"
                        values="
                            M0,192L48,186.7C96,181,192,171,288,181.3C384,192,480,224,576,213.3C672,203,768,149,864,138.7C960,128,1056,160,1152,176C1248,192,1344,192,1392,192L1440,192L1440,320L1392,320C1344,320,1248,320,1152,320C1056,320,960,320,864,320C768,320,672,320,576,320C480,320,384,320,288,320C192,320,96,320,48,320L0,320Z;
                            M0,160L48,176C96,192,192,224,288,213.3C384,203,480,149,576,138.7C672,128,768,160,864,176C960,192,1056,192,1152,192C1248,192,1344,192,1392,192L1440,192L1440,320L1392,320C1344,320,1248,320,1152,320C1056,320,960,320,864,320C768,320,672,320,576,320C480,320,384,320,288,320C192,320,96,320,48,320L0,320Z;
                            M0,192L48,186.7C96,181,192,171,288,181.3C384,192,480,224,576,213.3C672,203,768,149,864,138.7C960,128,1056,160,1152,176C1248,192,1344,192,1392,192L1440,192L1440,320L1392,320C1344,320,1248,320,1152,320C1056,320,960,320,864,320C768,320,672,320,576,320C480,320,384,320,288,320C192,320,96,320,48,320L0,320Z"
                    />
                </path>
            </Box>

            <Box
                as={motion.div}
                initial={{ scale: 0.8, opacity: 0 }}
                animate={{ scale: 1, opacity: 1 }}
                transition={{ duration: 0.5 }}
                maxW="sm"
                width="full"
                p={8}
                bg="rgba(255, 255, 255, 0.85)"
                borderRadius="2xl"
                boxShadow="xl"
                backdropFilter="blur(12px)"
                border="1px solid rgba(255, 255, 255, 0.3)"
            >
                {/* Cute logo/icon */}
                <Flex justify="center" mb={4}>
                    <Box
                        as="svg"
                        width="64px"
                        height="64px"
                        viewBox="0 0 24 24"
                        fill="none"
                        xmlns="http://www.w3.org/2000/svg"
                    >
                        <path
                            d="M12 21C16.9706 21 21 16.9706 21 12C21 7.02944 16.9706 3 12 3C7.02944 3 3 7.02944 3 12C3 16.9706 7.02944 21 12 21Z"
                            stroke="#FF6B6B"
                            strokeWidth="2"
                        />
                        <path
                            d="M8 12H16"
                            stroke="#FF6B6B"
                            strokeWidth="2"
                            strokeLinecap="round"
                        />
                        <path
                            d="M12 8V16"
                            stroke="#FF6B6B"
                            strokeWidth="2"
                            strokeLinecap="round"
                        />
                        <animateTransform
                            attributeName="transform"
                            type="rotate"
                            from="0 12 12"
                            to="360 12 12"
                            dur="5s"
                            repeatCount="indefinite"
                        />
                    </Box>
                </Flex>

                <Heading
                    size="lg"
                    mb={6}
                    textAlign="center"
                    fontFamily="'Poppins', sans-serif"
                    bgGradient="linear(to-r, pink.400, purple.500)"
                    bgClip="text"
                >
                    Admin Login
                </Heading>

                <Stack spacing={5}>
                    <FormControl isInvalid={!!error}>
                        <FormLabel fontFamily="'Poppins', sans-serif" color="gray.600">
                            Username
                        </FormLabel>
                        <Input
                            value={username}
                            onChange={(e) => setUsername(e.target.value)}
                            placeholder="Enter username"
                            bg="white"
                            borderRadius="full"
                            border="1px solid"
                            borderColor="gray.200"
                            _focus={{
                                borderColor: 'pink.400',
                                boxShadow: '0 0 0 3px rgba(255, 107, 107, 0.2)',
                            }}
                            _hover={{ borderColor: 'pink.300' }}
                            fontFamily="'Poppins', sans-serif"
                            transition="all 0.3s"
                        />
                    </FormControl>

                    <FormControl isInvalid={!!error}>
                        <FormLabel fontFamily="'Poppins', sans-serif" color="gray.600">
                            Password
                        </FormLabel>
                        <Input
                            type="password"
                            value={password}
                            onChange={(e) => setPassword(e.target.value)}
                            placeholder="Enter password"
                            bg="white"
                            borderRadius="full"
                            border="1px solid"
                            borderColor="gray.200"
                            _focus={{
                                borderColor: 'pink.400',
                                boxShadow: '0 0 0 3px rgba(255, 107, 107, 0.2)',
                            }}
                            _hover={{ borderColor: 'pink.300' }}
                            fontFamily="'Poppins', sans-serif"
                            transition="all 0.3s"
                        />
                    </FormControl>

                    <Button
                        as={motion.button}
                        whileHover={{ scale: 1.05, animation: `${bounce} 0.3s` }}
                        whileTap={{ scale: 0.95 }}
                        colorScheme="pink"
                        width="full"
                        borderRadius="full"
                        bgGradient="linear(to-r, pink.400, purple.500)"
                        _hover={{ bgGradient: 'linear(to-r, pink.500, purple.600)' }}
                        fontFamily="'Poppins', sans-serif"
                        fontWeight="bold"
                        onClick={handleLogin}
                        isDisabled={isLoading}
                        aria-label="Login"
                    >
                        {isLoading ? <Spinner size="sm" color="white" /> : 'Login'}
                    </Button>

                    <Text
                        textAlign="center"
                        fontFamily="'Poppins', sans-serif"
                        color="gray.600"
                    >
                        Don't have an account?{' '}
                        <Button
                            variant="link"
                            color="purple.500"
                            fontWeight="medium"
                            _hover={{ color: 'purple.600', textDecoration: 'underline' }}
                            onClick={() => navigate('/admin/register')}
                            aria-label="Register"
                        >
                            Register
                        </Button>
                    </Text>
                </Stack>
            </Box>
        </Flex>
    );
};

export default AdminLogin;