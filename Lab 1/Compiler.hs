{-# LANGUAGE GeneralizedNewtypeDeriving #-}
module TypeChecker where

import Absjavalette
import Printjavalette
import ErrM

import Control.Monad
import Control.Monad.State
import Control.Monad.Trans
import Control.Monad (liftM2)

import Data.Map (Map)
import qualified Data.Map as Map

-- Encapsulate environment in a state monad as to enable error and state handling at the same time 
newtype TCM m a = TCM { unTCM :: StateT Env m a }
    deriving (Monad, MonadTrans, MonadState Env)

-- Type alias to increase readability
type TC a = TCM Err a

-- Replace [(from,to)]
data Env = Env { -- all the type signatures from all the functions
                      signatures :: Map Ident ([Type], Type)
                    , contexts :: [Map Ident Type]
		    , returnType :: Type }

stdFuncs = [(Ident "printInt", ([Int],Void)),
	    (Ident "readInt", ([],Int)),
	    (Ident "printDouble", ([Doub],Void)),
	    (Ident "readDouble", ([],Doub))]	

-- Create an empty environment
emptyEnv :: Env
emptyEnv = Env { signatures = Map.fromList stdFuncs
               , contexts = [Map.empty]
	       , returnType = undefined }

compile :: Program -> Err ()
compile p = (evalStateT . unTCM) (checkTree p) emptyEnv

-- place one empty context at the top of the stack
pushContext :: TC ()
pushContext = modify (\e -> e { contexts = (Map.empty :  contexts e)})

-- remove topmost context from the stack
popContext :: TC ()
popContext = do
        ctxStack <- gets contexts
        when (null ctxStack) (error "popping from an empty context stack")
        modify (\e -> e { contexts = tail ctxStack })

-- add a variable to current context and fail if it already exists
addVar :: Ident -> Type -> TC ()
addVar n t = do
        env <- get
        let (c:cs) = contexts env
        when (Map.member n c) $ fail $ "adding a variable " ++ (show n) ++ " that is already in top context"
        let c' = Map.insert n t c
        let env' = env { contexts = (c' : cs) }
        put env'

-- add a function definition
addDef :: TopDef -> TC ()
addDef (FnDef retType n as _) = do
	sigs <- gets signatures 
	let ts = map argToType as
	let sigs' = Map.insert n (ts,retType) sigs
	modify (\e -> e { signatures = sigs' } ) -- updates the state record signatures
	where 
	argToType :: Arg -> Type
	argToType (Arg t _) = t

--addDef (FnDef Void printInt 
	
-- Look for a variable in allall the contextss
lookVar :: Ident -> TC Type
lookVar n = do
        ctxs <- gets contexts 
        rtrn (catMaybes ((map (Map.lookup n) ctxs)))
        where
	-- if we cant find anything, make sure we fail
        rtrn :: [Type] -> TC Type
        rtrn [] = fail $ "type of " ++ (show n) ++ " not found"
        rtrn (x:xs) = return x

-- Look for a function in the signatures
lookFun :: Ident -> TC ([Type], Type)
lookFun fName = do
	mbtSig <- gets (Map.lookup fName. signatures)
	when (isNothing mbtSig) (fail $ "Unknown function name")
	return $ fromJust mbtSig
	

inferExp :: Expr -> TC Type
inferExp expr = do
	case expr of
		EVar name 		-> do
			varName <- lookVar name
			return varName
		ELitInt i 		-> return Int 
		ELitDoub d 		-> return Doub
		ELitTrue		-> return Bool
		ELitFalse		-> return Bool
		EApp n expList 		-> do
			(argListTypes,returnType) <- lookFun n
			inferredTypes <- mapM inferExp expList
			when (inferredTypes /= argListTypes) (fail $ "Function " ++ (show n) ++ " passed with incorrect argument types")
			return returnType
		EAppS (Ident "printString") str -> return Void
		EAppS n str		-> do
			(argListTypes,returnType) <- lookFun n
			when (length argListTypes /= 1) (fail $ "Expected 1 parameter for function " ++ (show n)) -- LOL STRING
			return returnType
		Neg expr		-> do
			exprVal <- inferExp expr
			when (exprVal /= Int && exprVal /= Doub) (fail $ "Negation requires either Int or Double. " ++ (show exprVal) ++ " was passed.")
			return exprVal			
		Not expr		-> do
			exprVal <- inferExp expr
			when (exprVal /= Bool) (fail $ "Not expression requires Bool. " ++ (show exprVal) ++ " was passed.")
			return exprVal			
		EMul e0 op e1		-> checkBinaryOperation e0 e1
		EAdd e0 op e1		-> checkBinaryOperation e0 e1
		ERel e0 (EQU) e1 	-> do
			typ0 <- inferExp e0
			typ1 <- inferExp e1
			when (typ0 /= typ1) (fail $ "Trying to compare two expressions with different type (" ++ (show typ0) ++ " and " ++ (show typ1) ++ ")")
			return Bool
		ERel e0 op e1		-> do
			checkBinaryOperation e0 e1
			return Bool
		EAnd e0 e1		-> checkBoolean e0 e1
		EOr e0 e1		-> checkBoolean e0 e1
		

-- Check unary numeric operations such as ++ (exp)
checkUnaryOperation :: Expr -> TC Type
checkUnaryOperation exp = do
		iType <- inferExp exp
		if elem iType [Int, Doub] 
			then return iType 
			else fail $ (show iType) ++ "invalid expression" 

-- Check binary numeric operations 
checkBinaryOperation :: Expr -> Expr -> TC Type
checkBinaryOperation e0 e1 = do 
		iType0 <- inferExp e0
		iType1 <- inferExp e1
		if (iType0 == iType1 && iType0 /= Bool && iType0 /= Void)
			then return iType0
			else fail $ "Arithmetic operation have different (or invalid) argument types: " ++ (show iType0) ++ "," ++ (show iType1) 

checkComparator :: Expr -> Expr -> TC Type
checkComparator e0 e1 = do
		iType0 <- inferExp e0
		iType1 <- inferExp e1
		if iType0 == iType1
			then return Bool
			else fail $ "Cannot compare " ++ (show iType0) ++ " with " ++ (show iType1)
		
checkBoolean :: Expr -> Expr -> TC Type
checkBoolean e0 e1 = do
		iType0 <- inferExp e0
		iType1 <- inferExp e1
		if iType0 == Bool && iType1 == Bool
			then return Bool
			else fail $ "Boolean operation has different argument types: " ++ (show iType0) ++ "," ++ (show iType1)

checkStm :: Stmt -> TC ()
checkStm stm = do
	case stm of
		SType t stmt 		-> undefined
		Empty 			-> undefined
		BStmt (Block stmts) 	-> undefined
			
		Decl  t itmList		-> undefined
		  			
		Ass name epxr		-> undefined
		     
		Incr name		-> undefined
		   
		Decr name		-> undefined
		   
		Ret  expr     		-> undefined
		 
		VRet     		-> undefined
		   
		Cond expr stmt		-> undefined
		   
		CondElse  expr ifs els  -> undefined
		 
		While expr stmt		-> undefined
  		 
		SExp exprs		-> undefined
		
checkDef :: TopDef -> TC ()
checkDef (FnDef retType name args (Block stms)) = do
	pushContext
	modify (\e -> e { returnType = retType } )
	mapM_ addArgs args  
	mapM checkStm stms
	popContext
	return()
	where
	addArgs :: Arg -> TC ()
	addArgs (Arg t i) = addVar i t

checkTree (Program defs) = do
	mapM addDef defs
	mapM checkDef defs
	return ()