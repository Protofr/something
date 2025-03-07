import React, { useState, useEffect } from 'react';
import './TodoList.css';
import TodoItem from './TodoItem';
import { DragDropContext, Droppable, Draggable } from 'react-beautiful-dnd';

function TodoList() {
    const [todos, setTodos] = useState(
        JSON.parse(localStorage.getItem('todos')) || []
    );

    function separateTodos() {
        const importantTodos = todos.filter(todo => todo.important);
        const defaultTodos = todos.filter(todo => !todo.important);
        return { importantTodos, defaultTodos };
    }

    function handleAddTodo(event) {
        var x;
        x = document.getElementById("todo-input").value;
        if (x === "") {
            event.preventDefault();
            return false;
        } else {
            event.preventDefault();
            const input = event.target.elements.todo;
            const todo = {
                id: new Date().getTime().toString(), // Add unique ID
                text: input.value,
                completed: false,
                editing: false,
                important: false // Initialize important to false
            };

            setTodos([...todos, todo]);
            input.value = '';
        }
    }

    function handleCompleteTodo(todoId) {
        const newTodos = todos.map(t => (t.id === todoId ? { ...t, completed: !t.completed } : t));
        setTodos(newTodos);
        localStorage.setItem('todos', JSON.stringify(newTodos));
    }

    function handleDeleteTodo(todoId) {
        const newTodos = todos.filter(t => t.id !== todoId);
        setTodos(newTodos);
        localStorage.setItem('todos', JSON.stringify(newTodos));
    }

    function handleClear() {
        localStorage.clear();
        setTodos([]);
    }

    useEffect(() => {
        localStorage.setItem('todos', JSON.stringify(todos));
    }, [todos]);

    function handleEditTodo(todoId) {
        const newTodos = todos.map(t =>
            t.id === todoId ? { ...t, editing: true } : t
        );
        setTodos(newTodos);
    }

    function handleSaveTodo(todoId, event) {
        event.preventDefault();
        const input = event.target.elements.editTodo;
        const newTodos = todos.map(t =>
            t.id === todoId ? { ...t, text: input.value, editing: false } : t
        );
        setTodos(newTodos);
        localStorage.setItem('todos', JSON.stringify(newTodos));
    }

    function handleMarkImportant(todoId) {
        const newTodos = todos.map(t =>
            t.id === todoId ? { ...t, important: !t.important } : t
        );
        setTodos(newTodos);
        localStorage.setItem('todos', JSON.stringify(newTodos));
    }

    function toggleAddTodoVisibility() {
        const addTodoContainer = document.querySelector('.add-todo-container');
        addTodoContainer.classList.toggle('show');
    }

    const onDragEnd = (result) => {
        if (!result.destination) {
            return;
        }

        const { source, destination } = result;

        if (source.droppableId !== destination.droppableId) {
            return; // Handle moving between lists if you have multiple lists
        }

        const reorderedTodos = Array.from(todos);
        const [removed] = reorderedTodos.splice(source.index, 1);
        reorderedTodos.splice(destination.index, 0, removed);

        setTodos(reorderedTodos);
    };


    const { importantTodos, defaultTodos } = separateTodos();

    return (
        <DragDropContext onDragEnd={onDragEnd}>
            <div className="main">
                <div className="top">
                    <button className="check-icon-wrapper">
                        <svg width="12" height="12" viewBox="0 0 24 24">
                            <path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z" />
                        </svg>
                    </button>

                    <h1>Todo List</h1>
                </div>

                {importantTodos.length > 0 ? (
                    <>
                        <h2>Important</h2>
                        <Droppable droppableId="important-todos-list">
                            {(provided) => (
                                <ul
                                    className='todos-list'
                                    {...provided.droppableProps}
                                    ref={provided.innerRef}
                                >
                                    {importantTodos.map((todo, index) => (
                                        <Draggable key={todo.id} draggableId={todo.id} index={index}>
                                            {(provided) => (
                                                <li
                                                    ref={provided.innerRef}
                                                    {...provided.draggableProps}
                                                    {...provided.dragHandleProps}
                                                >
                                                    <TodoItem
                                                        todo={todo}
                                                        handleCompleteTodo={() => handleCompleteTodo(todo.id)}
                                                        handleEditTodo={() => handleEditTodo(todo.id)}
                                                        handleSaveTodo={event => handleSaveTodo(todo.id, event)}
                                                        handleDeleteTodo={() => handleDeleteTodo(todo.id)}
                                                        handleMarkImportant={() => handleMarkImportant(todo.id)}
                                                    />
                                                </li>
                                            )}
                                        </Draggable>
                                    ))}
                                    {provided.placeholder}
                                </ul>
                            )}
                        </Droppable>
                    </>
                ) : (
                    <></>
                )}

                <h2>Tasks</h2>
                <Droppable droppableId="default-todos-list">
                    {(provided) => (
                        <ul
                            className='todos-list'
                            {...provided.droppableProps}
                            ref={provided.innerRef}
                        >
                            {defaultTodos.length > 0 ? (
                                defaultTodos.map((todo, index) => (
                                    <Draggable key={todo.id} draggableId={todo.id} index={index}>
                                        {(provided) => (
                                            <li
                                                ref={provided.innerRef}
                                                {...provided.draggableProps}
                                                {...provided.dragHandleProps}
                                            >
                                                <TodoItem
                                                    todo={todo}
                                                    handleCompleteTodo={() => handleCompleteTodo(todo.id)}
                                                    handleEditTodo={() => handleEditTodo(todo.id)}
                                                    handleSaveTodo={event => handleSaveTodo(todo.id, event)}
                                                    handleDeleteTodo={() => handleDeleteTodo(todo.id)}
                                                    handleMarkImportant={() => handleMarkImportant(todo.id)}
                                                />
                                            </li>
                                        )}
                                    </Draggable>
                                ))
                            ) : (
                                <></>
                            )}
                            {provided.placeholder}
                        </ul>
                    )}
                </Droppable>


                {(importantTodos.length === 0 && defaultTodos.length === 0) &&
                    <div className="done">
                        <p className="empty-state">No todo items yet.</p>
                    </div>
                }

                <form onSubmit={handleAddTodo} className="add-todo-container">
                    <button type="button" onClick={toggleAddTodoVisibility} className="no-fill-icon-button">
                        <svg xmlns="http://www.w3.org/2000/svg" className="ionicon" viewBox="0 0 512 512"><title>Close</title><path fill="none" stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" strokeWidth="32" d="M368 368L144 144M368 144L144 368" /></svg>
                    </button>

                    <input type="text" name="todo" id="todo-input" autoComplete="off" className="add-input" placeholder="What to do today?.." />
                    <button type="submit" className="add-button" onClick={toggleAddTodoVisibility}>
                        <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 16 16" fill="none">
                            <path d="M8 3.5V12.5M12.5 8H3.5" stroke="white" strokeLinecap="round" strokeLinejoin="round" />
                        </svg>
                        <span>Add</span>
                    </button>
                </form>

                <button onClick={toggleAddTodoVisibility} className="mobile-toggle-drawer">
                    <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16" fill="none">
                        <path d="M8 3.5V12.5M12.5 8H3.5" stroke="white" strokeLinecap="round" strokeLinejoin="round" />
                    </svg>
                </button>
            </div >
        </DragDropContext>
    );
}

export default TodoList;
