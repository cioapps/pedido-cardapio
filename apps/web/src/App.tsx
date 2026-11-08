import { lazy, Suspense } from 'react'
import { BrowserRouter, Route, Routes, useParams } from 'react-router-dom'
import { PaginaCardapio } from './cardapio/PaginaCardapio'
import { PaginaPedido } from './cardapio/PaginaPedido'

const PaginaAdmin = lazy(() => import('./admin/PaginaAdmin'))

function Inicio() {
  return (
    <div className="grid min-h-dvh place-items-center p-6 text-center">
      <div className="max-w-md">
        <h1 className="text-3xl font-bold">Cardápio Online</h1>
        <p className="mt-3 text-zinc-600">
          Seu cardápio digital com pedidos direto na cozinha. Monte em minutos e envie o link no WhatsApp.
        </p>
        <p className="mt-6 text-zinc-600">
          É lojista? Cadastre seu cardápio e receba os pedidos pelo nosso app para Android.
        </p>
      </div>
    </div>
  )
}

/** Remonta o cardápio ao trocar de loja (carrinho é por loja) */
function CardapioPorSlug() {
  const { slug } = useParams()
  return <PaginaCardapio key={slug} />
}

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<Inicio />} />
        <Route
          path="/admin"
          element={
            <Suspense fallback={<div className="p-10 text-center text-zinc-500">Carregando...</div>}>
              <PaginaAdmin />
            </Suspense>
          }
        />
        <Route path="/:slug" element={<CardapioPorSlug />} />
        <Route path="/:slug/pedido/:codigo" element={<PaginaPedido />} />
      </Routes>
    </BrowserRouter>
  )
}
