import React, { useState, useEffect } from 'react';
import {
  Heading,
  useToast,
  Icon,
  Container,
  ChakraProvider,
  Box,
  FormControl,
  FormLabel,
  Input,
  InputGroup,
  InputLeftElement,
  Radio,
  RadioGroup,
  Stack,
  Button,
  VStack,
  Spinner,
  Flex,
  IconButton,
  Modal,
  ModalOverlay,
  ModalContent,
  ModalHeader,
  ModalCloseButton,
  ModalBody,
  Text
} from '@chakra-ui/react';
import { FaDollarSign, FaUser } from 'react-icons/fa';

import { PageLayout } from './components/PageLayout';

import { AuthenticatedTemplate, UnauthenticatedTemplate, useMsal, useMsalAuthentication } from '@azure/msal-react';

import './App.css';

/**
* If a user is authenticated the ProfileContent component above is rendered. Otherwise a message indicating a user is not authenticated is rendered.
*/
const MainContent = () => {
  const {login, result, error} = useMsalAuthentication("redirect");
  
  return (
    <div className="App">
      <AuthenticatedTemplate>
        <ChakraProvider>
          <Box bg="gray.100" minHeight="100vh">
            <WebForm />
          </Box>
        </ChakraProvider>
      </AuthenticatedTemplate>

      <UnauthenticatedTemplate>
        <h5>
          <center>
            Please sign-in to create a sandbox.
          </center>
        </h5>
      </UnauthenticatedTemplate>
    </div>
  );
};

export default function App() {
  return (
    <PageLayout>
      <center>
        <MainContent />
      </center>
    </PageLayout>

  );
};

const WebForm = () => {
  const toast = useToast();
  var { instance, accounts } = useMsal();
  const [ManagerEmail, setManagerEmail] = useState('');
  const [Budget, setBudget] = useState('');
  const [Length, setLength] = useState('');
  const [CostCenter, setCostCenter] = useState([]);
  const [isValid, setIsValid] = useState(false);
  const [isLoading, setIsLoading] = useState(false);

  const [isModalOpen, setIsModalOpen] = useState(false);

  const handleUserIconClick = () => {
    setIsModalOpen(true);
  };

  const handleCloseModal = () => {
    setIsModalOpen(false);
  };

  useEffect(() => {
    if (Budget !== '' && Length !== '') {
      setIsValid(true);
    } else {
      setIsValid(false);
    }
  }, [Budget, Length]);

  const handleSubmit = async (e) => {
    e.preventDefault();
    setIsLoading(true);

    const payload = {
      "FirstName": (accounts[0].name).split(" ")[0],
      "LastName": (accounts[0].name).split(" ")[1],
      "Email": (accounts[0].username),
      "ObjectID": (accounts[0].localAccountId),
      ManagerEmail,
      Budget,
      Length,
      CostCenter,
    };

    try {
      const response = await fetch('https://func-sandboxmgmt-prod.azurewebsites.net/api/create', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-functions-key': 'G5JbjU7eXU-MwyqDFbR1N0cJfILyqK8ESuAQWw0Vy6UiAzFuuMxqMw=='
        },
        body: JSON.stringify(payload),
      });

      if (response.ok) {
        toast({
          title: 'Submission successful',
          description: 'Your form has been submitted successfully.',
          status: 'success',
          duration: 3000,
          isClosable: true,
          position: 'top',
        });
        setIsLoading(false);
      } else {
        toast({
          title: 'Submission failed',
          description: 'There was a problem submitting your form.',
          status: 'error',
          duration: 3000,
          isClosable: true,
          position: 'top',
        });
        setIsLoading(false);
      }
    } catch (error) {
      toast({
        title: 'Submission failed',
        description: 'There was a problem submitting your form. ',
        status: 'error',
        duration: 3000,
        isClosable: true,
        position: 'top',
      });
      setIsLoading(false);
    }
  };

  return (
    <Container maxW="container.md" py={8}>
      <Box
        bg="white"
        boxShadow="base"
        borderRadius="md"
        p={6}
        mx="auto"
        mt={4}
        width="100%"
      >
        <Flex alignItems="center" mb={4}>
          <Heading as="h1" size="lg" flex="1">
            Sandbox Request
          </Heading>
          {accounts[0].name.split(" ")[0]}
          <IconButton
            aria-label="User Icon"
            icon={<FaUser />}
            variant="ghost"
            onClick={handleUserIconClick}
          />
        </Flex>
        <form onSubmit={handleSubmit}>
          <VStack spacing={4}>
            <FormControl>
              <FormLabel>Manager Email</FormLabel>
              <InputGroup>
                <Input
                  type="string"
                  placeholder="Boss.Doe@company.com"
                  value={ManagerEmail}
                  onChange={(e) => setManagerEmail(e.target.value)}
                />
              </InputGroup>
            </FormControl>

            <FormControl>
              <FormLabel>Budget</FormLabel>
              <InputGroup>
                <InputLeftElement pointerEvents="none">
                  <Icon as={FaDollarSign} />
                </InputLeftElement>
                <Input
                  type="number"
                  placeholder="Budget"
                  value={Budget}
                  onChange={(e) => setBudget(e.target.value)}
                />
              </InputGroup>
            </FormControl>

            <FormControl>
              <FormLabel>Cost Center</FormLabel>
              <InputGroup>
                <Input
                  type="string"
                  placeholder="12345-123"
                  value={CostCenter}
                  onChange={(e) => setCostCenter(e.target.value)}
                />
              </InputGroup>
            </FormControl>

            <FormControl>
              <FormLabel>Length</FormLabel>
              <RadioGroup onChange={setLength} value={Length}>
                <Stack direction="row">
                  <Radio value="1">1</Radio>
                  <Radio value="2">2</Radio>
                  <Radio value="3">3</Radio>
                </Stack>
              </RadioGroup>
            </FormControl>

            <Button type="submit" colorScheme="blue" isDisabled={!isValid || isLoading}>
              {isLoading ? <Spinner size="sm" mr={2} /> : null}
              Submit
            </Button>
          </VStack>
        </form>
      </Box>
      <Modal isOpen={isModalOpen} onClose={handleCloseModal}>
        <ModalOverlay />
        <ModalContent>
          <ModalHeader>User Info</ModalHeader>
          <ModalCloseButton />
          <ModalBody>
            <Text><b>Name:</b> {accounts[0].name}</Text>
            <Text><b>Email:</b> {accounts[0].username}</Text>
            <Text><b>Object ID:</b> {accounts[0].localAccountId}</Text>
          </ModalBody>
        </ModalContent>
      </Modal>
    </Container>
  );
}